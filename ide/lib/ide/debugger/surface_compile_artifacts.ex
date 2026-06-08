defmodule Ide.Debugger.SurfaceCompileArtifacts do
  @moduledoc false

  alias Ide.Compiler
  alias Ide.Debugger.CompileContract
  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.Surface
  alias Ide.Debugger.SurfaceTargets
  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.ElmcSurfaceFields
  alias Ide.ProjectTemplates
  alias Ide.Projects

  @type attach_ctx :: %{
          required(:session_key_from_state) => (Types.runtime_state() -> String.t() | nil),
          required(:source_root_for_target) => (Types.surface_target() -> String.t()),
          required(:merge_runtime_artifacts) => (Types.runtime_state(),
                                                 Types.surface_target(),
                                                 Types.elm_introspect() ->
                                                   Types.runtime_state())
        }

  @spec ensure_attached(Types.runtime_state(), Types.surface_target(), attach_ctx()) ::
          Types.runtime_state()
  def ensure_attached(state, target, ctx)
      when is_map(state) and target in [:watch, :companion, :phone] and is_map(ctx) do
    maybe_attach_for_parser_view(state, target, ctx)
  end

  def ensure_attached(state, _target, _ctx), do: state

  @spec maybe_attach_for_parser_view(
          Types.runtime_state(),
          Types.surface_target(),
          attach_ctx()
        ) :: Types.runtime_state()
  def maybe_attach_for_parser_view(state, target, ctx)
      when is_map(state) and target in [:watch, :companion, :phone] and is_map(ctx) do
    source_root = ctx.source_root_for_target.(target)

    cond do
      surface_has_versioned_runtime_artifacts?(state, target) ->
        attach_missing_debugger_contract(state, target, ctx)

      inline_source_present?(state, source_root) ->
        artifacts = artifacts_for_source_root(state, source_root, ctx)
        ctx.merge_runtime_artifacts.(state, target, artifacts)

      true ->
        artifacts = artifacts_for_source_root(state, source_root, ctx)
        ctx.merge_runtime_artifacts.(state, target, artifacts)
    end
  end

  def maybe_attach_for_parser_view(state, _target, _ctx), do: state

  @spec surface_has_versioned_runtime_artifacts?(Types.runtime_state(), Types.surface_target()) ::
          boolean()
  def surface_has_versioned_runtime_artifacts?(state, target)
      when is_map(state) and target in [:watch, :companion, :phone] do
    state
    |> Map.get(target, %{})
    |> RuntimeArtifacts.execution_model()
    |> RuntimeArtifacts.versioned_elmx_artifacts?()
  end

  def surface_has_versioned_runtime_artifacts?(_state, _target), do: false

  @spec artifacts_for_source_root(Types.runtime_state(), String.t(), attach_ctx()) ::
          Types.runtime_artifacts()
  @doc false
  @spec debugger_contract_for_reload(Types.runtime_state(), Types.surface_target(), attach_ctx()) ::
          Types.elm_introspect() | nil
  def debugger_contract_for_reload(state, target, ctx)
      when is_map(state) and target in [:watch, :companion, :phone] and is_map(ctx) do
    state
    |> artifacts_for_source_root(ctx.source_root_for_target.(target), ctx)
    |> CompileContract.from_artifacts()
  end

  def debugger_contract_for_reload(_state, _target, _ctx), do: nil

  @spec artifacts_for_source_root(Types.runtime_state(), String.t(), attach_ctx()) ::
          Types.runtime_artifacts()
  def artifacts_for_source_root(state, source_root, ctx)
      when is_map(state) and is_binary(source_root) and is_map(ctx) do
    inline_present? = inline_source_present?(state, source_root)

    inline_artifacts =
      if inline_present? do
        artifacts_from_inline_source(state, source_root, ctx)
      else
        %{}
      end

    cond do
      inline_present? and versioned_runtime_artifacts?(inline_artifacts) ->
        inline_artifacts

      versioned_runtime_artifacts?(inline_artifacts) ->
        inline_artifacts

      true ->
        project_artifacts = safe_project_entrypoint_artifacts(state, source_root, ctx)

        cond do
          versioned_runtime_artifacts?(project_artifacts) ->
            project_artifacts

          map_size(project_artifacts) > 0 ->
            project_artifacts

          true ->
            inline_artifacts
        end
    end
  end

  @spec safe_project_entrypoint_artifacts(Types.runtime_state(), String.t(), attach_ctx()) ::
          Types.runtime_artifacts()
  defp safe_project_entrypoint_artifacts(state, source_root, ctx)
       when is_map(state) and is_binary(source_root) and is_map(ctx) do
    project_entrypoint_artifacts(state, source_root, ctx)
  rescue
    DBConnection.OwnershipError ->
      %{}

    error in RuntimeError ->
      if String.contains?(Exception.message(error), "could not lookup Ecto repo") do
        %{}
      else
        reraise(error, __STACKTRACE__)
      end
  end

  @spec entrypoint_artifacts(String.t(), Ide.Projects.Project.t(), String.t()) ::
          Types.runtime_artifacts()
  def entrypoint_artifacts(session_key, project, source_root)
      when is_binary(session_key) and is_binary(source_root) do
    _ = Projects.ensure_compiler_workspace(project)

    workspace_root =
      project
      |> Projects.project_workspace_path()
      |> Path.join(source_root)

    case safe_compiler_compile(
           Projects.compiler_cache_key(session_key, source_root),
           workspace_root: workspace_root
         ) do
      {:ok, result} when is_map(result) ->
        ElmcSurfaceFields.optional_runtime_artifacts(result)

      _ ->
        %{}
    end
  end

  @spec project_entrypoint_artifacts(Types.runtime_state(), String.t(), attach_ctx()) ::
          Types.runtime_artifacts()
  defp project_entrypoint_artifacts(state, source_root, ctx)
       when is_map(state) and is_binary(source_root) and is_map(ctx) do
    with session_key when is_binary(session_key) <- ctx.session_key_from_state.(state),
         %{} = project <- Projects.get_project_by_scope_key(session_key) do
      entrypoint_artifacts(session_key, project, source_root)
    else
      _ -> %{}
    end
  end

  defp versioned_runtime_artifacts?(artifacts) when is_map(artifacts) do
    versioned_elmx_artifacts?(artifacts)
  end

  @spec versioned_elmx_artifacts?(Types.runtime_artifacts()) :: boolean()
  defp versioned_elmx_artifacts?(artifacts) when is_map(artifacts),
    do: RuntimeArtifacts.versioned_elmx_artifacts?(artifacts)

  @spec attach_missing_debugger_contract(
          Types.runtime_state(),
          Types.surface_target(),
          attach_ctx()
        ) ::
          Types.runtime_state()
  defp attach_missing_debugger_contract(state, target, ctx)
       when is_map(state) and target in [:watch, :companion, :phone] and is_map(ctx) do
    surface = Surface.from_state(state, target)

    if blank_introspect?(surface) do
      source_root = ctx.source_root_for_target.(target)

      artifacts =
        state
        |> artifacts_for_source_root(source_root, ctx)
        |> debugger_contract_artifacts_only()

      if map_size(artifacts) > 0 do
        ctx.merge_runtime_artifacts.(state, target, artifacts)
      else
        state
      end
    else
      state
    end
  end

  defp attach_missing_debugger_contract(state, _target, _ctx), do: state

  @spec blank_introspect?(Surface.t() | Surface.surface_map()) :: boolean()
  defp blank_introspect?(surface) do
    case RuntimeArtifacts.introspect(surface) do
      ei when is_map(ei) and map_size(ei) > 0 -> false
      _ -> true
    end
  end

  @spec debugger_contract_artifacts_only(Types.runtime_artifacts()) :: Types.runtime_artifacts()
  defp debugger_contract_artifacts_only(artifacts) when is_map(artifacts) do
    artifacts
    |> Map.take([
      "debugger_contract",
      "debugger_contract_b64",
      "debugger_contract_version",
      :debugger_contract,
      :debugger_contract_b64,
      :debugger_contract_version
    ])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  @spec inline_source_present?(Types.runtime_state(), String.t()) :: boolean()
  defp inline_source_present?(state, source_root) when is_map(state) and is_binary(source_root) do
    target = surface_target_for_source_root(source_root)
    model = get_in(state, [target, :model]) || %{}

    is_binary(Map.get(model, "last_source")) and String.trim(Map.get(model, "last_source")) != ""
  end

  @doc false
  @spec precompile_inline_artifacts(String.t(), String.t(), String.t(), String.t()) ::
          Types.runtime_artifacts()
  def precompile_inline_artifacts(session_key, source, rel_path, source_root)
      when is_binary(session_key) and is_binary(source) and is_binary(rel_path) and
             is_binary(source_root) do
    if String.trim(source) != "" do
      ephemeral_entrypoint_artifacts(session_key, source, rel_path, source_root)
    else
      %{}
    end
  end

  def precompile_inline_artifacts(_session_key, _source, _rel_path, _source_root), do: %{}

  @spec reload_precompiled_artifacts(Types.runtime_state(), String.t()) ::
          Types.runtime_artifacts()
  defp reload_precompiled_artifacts(state, source_root)
       when is_map(state) and is_binary(source_root) do
    case Map.get(state, :__reload_precompiled_artifacts__) do
      %{source_root: ^source_root, artifacts: artifacts} when is_map(artifacts) ->
        artifacts

      %{"source_root" => ^source_root, "artifacts" => artifacts} when is_map(artifacts) ->
        artifacts

      _ ->
        %{}
    end
  end

  @spec artifacts_from_inline_source(Types.runtime_state(), String.t(), attach_ctx()) ::
          Types.runtime_artifacts()
  defp artifacts_from_inline_source(state, source_root, ctx)
       when is_map(state) and is_binary(source_root) and is_map(ctx) do
    case reload_precompiled_artifacts(state, source_root) do
      precompiled when is_map(precompiled) and map_size(precompiled) > 0 ->
        precompiled

      _ ->
        target = surface_target_for_source_root(source_root)
        model = get_in(state, [target, :model]) || %{}

        source = Map.get(model, "last_source")
        rel_path = Map.get(model, "last_path")

        with true <- is_binary(source) and String.trim(source) != "",
             true <- is_binary(rel_path) and String.trim(rel_path) != "",
             session_key when is_binary(session_key) <- ctx.session_key_from_state.(state) do
          ephemeral_entrypoint_artifacts(session_key, source, rel_path, source_root)
        else
          _ -> %{}
        end
    end
  end

  @spec ephemeral_entrypoint_artifacts(String.t(), String.t(), String.t(), String.t()) ::
          Types.runtime_artifacts()
  @spec project_watch_workspace_root(String.t()) :: {:ok, String.t()} | :error
  defp project_watch_workspace_root(session_key) when is_binary(session_key) do
    with %{} = project <- Projects.get_project_by_scope_key(session_key) do
      _ = Projects.ensure_compiler_workspace(project)

      watch_root =
        project
        |> Projects.project_workspace_path()
        |> Path.join("watch")

      if File.dir?(watch_root), do: {:ok, watch_root}, else: :error
    else
      _ -> :error
    end
  rescue
    DBConnection.OwnershipError ->
      :error

    error in RuntimeError ->
      if String.contains?(Exception.message(error), "could not lookup Ecto repo") do
        :error
      else
        reraise(error, __STACKTRACE__)
      end
  end

  defp ephemeral_entrypoint_artifacts(session_key, source, rel_path, "phone")
       when is_binary(session_key) and is_binary(source) and is_binary(rel_path) do
    workspace = ephemeral_workspace_path(session_key, source, rel_path)
    phone_root = Path.join(workspace, "phone")
    dest_rel = normalize_phone_rel_path(rel_path)
    dest = Path.join(phone_root, dest_rel)

    unless File.dir?(phone_root) do
      File.rm_rf!(workspace)
      :ok = ProjectTemplates.seed_ephemeral_phone_compile_workspace(workspace)
    end

    File.mkdir_p!(Path.dirname(dest))
    File.write!(dest, source)

    default_companion = Path.join(phone_root, "src/CompanionApp.elm")

    if Path.expand(dest) != Path.expand(default_companion) and File.exists?(default_companion) do
      File.rm!(default_companion)
    end

    default_main = Path.join(phone_root, "src/Main.elm")

    if Path.expand(dest) != Path.expand(default_main) and File.exists?(default_main) and
         entry_module_from_path(dest) == "CompanionApp" do
      File.rm!(default_main)
    end

    compile_artifacts =
      case safe_compiler_compile(
             "debugger-inline-phone-#{session_key}-#{:erlang.phash2({rel_path, source})}",
             workspace_root: phone_root
           ) do
        {:ok, result} when is_map(result) ->
          ElmcSurfaceFields.optional_runtime_artifacts(result)

        _ ->
          %{}
      end

    compile_artifacts
  end

  defp ephemeral_entrypoint_artifacts(session_key, source, rel_path, "watch")
       when is_binary(session_key) and is_binary(source) and is_binary(rel_path) do
    workspace = ephemeral_workspace_path(session_key, source, rel_path)
    watch_dir = Path.join(workspace, "watch")
    dest_rel = normalize_watch_rel_path(rel_path)
    dest = Path.join(watch_dir, dest_rel)

    unless File.dir?(watch_dir) do
      File.rm_rf!(workspace)

      case project_watch_workspace_root(session_key) do
        {:ok, project_watch_root} ->
          File.mkdir_p!(workspace)
          File.cp_r!(project_watch_root, watch_dir)

        :error ->
          :ok = ProjectTemplates.apply_template("watch-demo-health", workspace)
          File.rm_rf!(Path.join(watch_dir, "src"))
          File.mkdir_p!(Path.join(watch_dir, "src"))
      end
    end

    File.mkdir_p!(Path.dirname(dest))
    File.write!(dest, source)

    default_main = Path.join(watch_dir, "src/Main.elm")

    if Path.expand(dest) != Path.expand(default_main) and File.exists?(default_main) do
      File.rm!(default_main)
    end

    compile_artifacts =
      case safe_compiler_compile(
             "debugger-inline-#{session_key}-#{:erlang.phash2({rel_path, source})}",
             workspace_root: watch_dir
           ) do
        {:ok, result} when is_map(result) ->
          ElmcSurfaceFields.optional_runtime_artifacts(result)

        _ ->
          %{}
      end

    compile_artifacts
  end

  @spec entry_module_from_path(String.t()) :: String.t()
  defp entry_module_from_path(path) when is_binary(path) do
    path |> Path.basename() |> Path.rootname()
  end

  @spec ephemeral_workspace_path(String.t(), String.t(), String.t()) :: String.t()
  defp ephemeral_workspace_path(session_key, source, rel_path) do
    safe_key =
      session_key
      |> String.replace(~r/[^a-zA-Z0-9._-]+/, "_")
      |> String.slice(0, 80)

    Path.join([
      System.tmp_dir!(),
      "ide-debugger-inline-#{safe_key}-#{:erlang.phash2({rel_path, source})}"
    ])
  end

  @spec surface_target_for_source_root(String.t()) :: Types.surface_target()
  defp surface_target_for_source_root("protocol"), do: :companion

  defp surface_target_for_source_root(source_root) when is_binary(source_root) do
    SurfaceTargets.normalize(source_root)
  end

  @spec normalize_phone_rel_path(String.t()) :: String.t()
  defp normalize_phone_rel_path(rel_path) when is_binary(rel_path) do
    cond do
      String.starts_with?(rel_path, "phone/src/") ->
        String.replace_prefix(rel_path, "phone/", "")

      String.match?(rel_path, ~r/^phone\/([^\/]+)\.elm$/) ->
        "src/#{Path.basename(rel_path)}"

      String.starts_with?(rel_path, "src/") ->
        rel_path

      String.ends_with?(rel_path, ".elm") ->
        "src/#{Path.basename(rel_path)}"

      true ->
        "src/CompanionApp.elm"
    end
  end

  @spec normalize_watch_rel_path(String.t()) :: String.t()
  defp normalize_watch_rel_path(rel_path) when is_binary(rel_path) do
    cond do
      String.starts_with?(rel_path, "watch/src/") ->
        String.replace_prefix(rel_path, "watch/", "")

      String.match?(rel_path, ~r/^watch\/([^\/]+)\.elm$/) ->
        "src/#{Path.basename(rel_path)}"

      String.starts_with?(rel_path, "src/") ->
        rel_path

      true ->
        "src/Main.elm"
    end
  end

  @spec safe_compiler_compile(String.t(), keyword()) ::
          {:ok, Ide.Compiler.compile_result()} | {:error, term()}
  defp safe_compiler_compile(cache_key, opts) when is_binary(cache_key) and is_list(opts) do
    Compiler.compile(cache_key, opts)
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, {:compile_exit, reason}}
  end
end
