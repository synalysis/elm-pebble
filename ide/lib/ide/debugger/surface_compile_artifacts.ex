defmodule Ide.Debugger.SurfaceCompileArtifacts do
  @moduledoc false

  alias ElmEx.CoreIR
  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.Lowerer
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
          required(:merge_runtime_artifacts) =>
            (Types.runtime_state(), Types.surface_target(), Types.elm_introspect() ->
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
      inline_source_present?(state, source_root) ->
        artifacts = artifacts_for_source_root(state, source_root, ctx)
        ctx.merge_runtime_artifacts.(state, target, artifacts)

      surface_has_versioned_runtime_artifacts?(state, target) ->
        attach_missing_debugger_contract(state, target, ctx)

      true ->
        artifacts = artifacts_for_source_root(state, source_root, ctx)
        ctx.merge_runtime_artifacts.(state, target, artifacts)
    end
  end

  def maybe_attach_for_parser_view(state, _target, _ctx), do: state

  @spec surface_has_core_ir?(Types.runtime_state(), Types.surface_target()) :: boolean()
  def surface_has_core_ir?(state, target),
    do: surface_has_versioned_core_ir?(state, target)

  @spec surface_has_versioned_core_ir?(Types.runtime_state(), Types.surface_target()) :: boolean()
  def surface_has_versioned_core_ir?(state, target)
      when is_map(state) and target in [:watch, :companion, :phone] do
    state
    |> Map.get(target, %{})
    |> RuntimeArtifacts.execution_model()
    |> RuntimeArtifacts.versioned_core_ir?()
  end

  def surface_has_versioned_core_ir?(_state, _target), do: false

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
    project_artifacts = safe_project_entrypoint_artifacts(state, source_root, ctx)

    inline_artifacts =
      if inline_source_present?(state, source_root) do
        artifacts_from_inline_source(state, source_root, ctx)
      else
        %{}
      end

    cond do
      inline_source_present?(state, source_root) and versioned_runtime_artifacts?(inline_artifacts) ->
        inline_artifacts

      versioned_runtime_artifacts?(project_artifacts) ->
        project_artifacts

      versioned_runtime_artifacts?(inline_artifacts) ->
        inline_artifacts

      map_size(project_artifacts) > 0 ->
        project_artifacts

      true ->
        inline_artifacts
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

    result =
      case Compiler.compile(Projects.compiler_cache_key(session_key, source_root),
             workspace_root: workspace_root
           ) do
        {:ok, compile_result} when is_map(compile_result) ->
          compile_result

        {:error, _} ->
          %{status: :error}
      end

    result
    |> ElmcSurfaceFields.optional_runtime_artifacts()
    |> maybe_merge_lenient_core_ir(workspace_root)
  rescue
    _ -> %{}
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

  @spec versioned_core_ir_artifacts?(Types.runtime_artifacts()) :: boolean()
  defp versioned_runtime_artifacts?(artifacts) when is_map(artifacts) do
    versioned_core_ir_artifacts?(artifacts) or versioned_elmx_artifacts?(artifacts)
  end

  defp versioned_core_ir_artifacts?(artifacts) when is_map(artifacts) do
    b64 = Map.get(artifacts, "elm_executor_core_ir_b64")

    is_binary(b64) and b64 != "" and
      RuntimeArtifacts.versioned_core_ir?(%{"elm_executor_core_ir_b64" => b64})
  end

  @spec versioned_elmx_artifacts?(Types.runtime_artifacts()) :: boolean()
  defp versioned_elmx_artifacts?(artifacts) when is_map(artifacts),
    do: RuntimeArtifacts.versioned_elmx_artifacts?(artifacts)

  @spec versioned_runtime_artifacts?(Types.runtime_state(), Types.surface_target()) :: boolean()
  defp versioned_runtime_artifacts?(state, target)
       when is_map(state) and target in [:watch, :companion, :phone] do
    execution_model =
      state
      |> Map.get(target, %{})
      |> RuntimeArtifacts.execution_model()

    RuntimeArtifacts.versioned_core_ir?(execution_model) or
      RuntimeArtifacts.versioned_elmx_artifacts?(execution_model)
  end

  @spec surface_has_versioned_runtime_artifacts?(Types.runtime_state(), Types.surface_target()) ::
          boolean()
  defp surface_has_versioned_runtime_artifacts?(state, target),
    do: versioned_runtime_artifacts?(state, target)

  @spec attach_missing_debugger_contract(Types.runtime_state(), Types.surface_target(), attach_ctx()) ::
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

  @spec artifacts_from_inline_source(Types.runtime_state(), String.t(), attach_ctx()) ::
          Types.runtime_artifacts()
  defp artifacts_from_inline_source(state, source_root, ctx)
       when is_map(state) and is_binary(source_root) and is_map(ctx) do
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
    DBConnection.OwnershipError -> :error

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
      case Compiler.compile(
             "debugger-inline-phone-#{session_key}-#{:erlang.phash2({rel_path, source})}",
             workspace_root: phone_root
           ) do
        {:ok, result} when is_map(result) ->
          result
          |> ElmcSurfaceFields.optional_runtime_artifacts()
          |> maybe_merge_lenient_core_ir(phone_root)

        {:error, _reason} ->
          lenient_core_ir_artifact_fields(phone_root, entry_module_from_path(dest))
      end

    if map_size(compile_artifacts) > 0 do
      compile_artifacts
    else
      lenient_core_ir_artifact_fields(phone_root, entry_module_from_path(dest))
    end
  rescue
    _error ->
      session_key
      |> ephemeral_workspace_path(source, rel_path)
      |> Path.join("phone")
      |> lenient_core_ir_artifact_fields(entry_module_from_rel_path(rel_path))
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
      case Compiler.compile(
             "debugger-inline-#{session_key}-#{:erlang.phash2({rel_path, source})}",
             workspace_root: watch_dir
           ) do
        {:ok, result} when is_map(result) ->
          result
          |> ElmcSurfaceFields.optional_runtime_artifacts()
          |> maybe_merge_lenient_core_ir(watch_dir)

        {:error, _reason} ->
          lenient_core_ir_artifact_fields(watch_dir, entry_module_from_path(dest))
      end

    if map_size(compile_artifacts) > 0 do
      compile_artifacts
    else
      lenient_core_ir_artifact_fields(watch_dir, entry_module_from_path(dest))
    end
  rescue
    _error ->
      session_key
      |> ephemeral_workspace_path(source, rel_path)
      |> Path.join("watch")
      |> lenient_core_ir_artifact_fields(entry_module_from_rel_path(rel_path))
  end

  @spec entry_module_from_path(String.t()) :: String.t()
  defp entry_module_from_path(path) when is_binary(path) do
    path |> Path.basename() |> Path.rootname()
  end

  @spec entry_module_from_rel_path(String.t()) :: String.t()
  defp entry_module_from_rel_path(rel_path) when is_binary(rel_path) do
    rel_path
    |> normalize_watch_rel_path()
    |> Path.basename()
    |> Path.rootname()
  end

  @spec maybe_merge_lenient_core_ir(Types.runtime_artifacts(), String.t()) :: Types.runtime_artifacts()
  defp maybe_merge_lenient_core_ir(artifacts, project_dir) when is_map(artifacts) and is_binary(project_dir) do
    b64 = Map.get(artifacts, "elm_executor_core_ir_b64")

    if is_binary(b64) and b64 != "" do
      artifacts
    else
      Map.merge(artifacts, lenient_core_ir_artifact_fields(project_dir, default_entry_module(project_dir)))
    end
  end

  @spec default_entry_module(String.t()) :: String.t()
  defp default_entry_module(project_dir) when is_binary(project_dir),
    do: Ide.Compiler.default_elmx_entry_module(project_dir)

  @spec lenient_core_ir_artifact_fields(String.t(), String.t()) :: Types.runtime_artifacts()
  defp lenient_core_ir_artifact_fields(project_dir, entry_module)
       when is_binary(project_dir) and is_binary(entry_module) do
    with {:ok, project} <- Bridge.load_project(project_dir),
         {:ok, ir} <- Lowerer.lower_project(project),
         {:ok, core_ir, validation_mode} <- core_ir_from_lowered_ir(ir) do
      _ = project

      %{
        "elm_executor_core_ir_b64" => core_ir |> :erlang.term_to_binary() |> Base.encode64(),
        "elm_executor_metadata" => %{
          "compiler" => "elm_executor",
          "contract" => "elm_executor.runtime_executor.v1",
          "mode" => "ide_runtime",
          "entry_module" => to_string(entry_module),
          "core_ir_validation" => validation_mode
        }
      }
    else
      _ -> %{}
    end
  end

  @spec core_ir_from_lowered_ir(map()) ::
          {:ok, CoreIR.t() | map(), String.t()} | {:error, term()}
  defp core_ir_from_lowered_ir(ir) when is_map(ir) do
    case CoreIR.from_ir(ir, strict?: true) do
      {:ok, core_ir} ->
        {:ok, core_ir, "strict"}

      {:error, _} ->
        case CoreIR.from_ir(ir, strict?: false) do
          {:ok, core_ir} -> {:ok, core_ir, "lenient"}
          {:error, reason} -> {:error, reason}
        end
    end
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
end
