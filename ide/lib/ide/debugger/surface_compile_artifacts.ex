defmodule Ide.Debugger.SurfaceCompileArtifacts do
  @moduledoc false

  alias Ide.Compiler
  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.ElmcSurfaceFields
  alias Ide.Projects

  @type attach_ctx :: %{
          required(:session_key_from_state) => (Types.runtime_state() -> String.t() | nil),
          required(:source_root_for_target) => (Types.surface_target() -> String.t()),
          required(:merge_runtime_artifacts) =>
            (Types.runtime_state(), Types.surface_target(), map() -> Types.runtime_state())
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
    if surface_has_core_ir?(state, target) do
      state
    else
      source_root = ctx.source_root_for_target.(target)
      artifacts = artifacts_for_source_root(state, source_root, ctx)
      ctx.merge_runtime_artifacts.(state, target, artifacts)
    end
  end

  def maybe_attach_for_parser_view(state, _target, _ctx), do: state

  @spec surface_has_core_ir?(Types.runtime_state(), Types.surface_target()) :: boolean()
  def surface_has_core_ir?(state, target) when is_map(state) and target in [:watch, :companion, :phone] do
    state
    |> Map.get(target, %{})
    |> RuntimeArtifacts.execution_model()
    |> RuntimeArtifacts.decode_core_ir()
    |> is_map()
  end

  def surface_has_core_ir?(_state, _target), do: false

  @spec artifacts_for_source_root(Types.runtime_state(), String.t(), attach_ctx()) :: map()
  def artifacts_for_source_root(state, source_root, ctx)
      when is_map(state) and is_binary(source_root) and is_map(ctx) do
    with session_key when is_binary(session_key) <- ctx.session_key_from_state.(state),
         %{} = project <- Projects.get_project_by_scope_key(session_key) do
      entrypoint_artifacts(session_key, project, source_root)
    else
      _ -> %{}
    end
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

  @spec entrypoint_artifacts(String.t(), map(), String.t()) :: map()
  def entrypoint_artifacts(session_key, project, source_root)
      when is_binary(session_key) and is_binary(source_root) do
    _ = Projects.ensure_compiler_workspace(project)

    workspace_root =
      project
      |> Projects.project_workspace_path()
      |> Path.join(source_root)

    {:ok, result} =
      Compiler.compile(Projects.compiler_cache_key(session_key, source_root),
        workspace_root: workspace_root
      )

    ElmcSurfaceFields.optional_runtime_artifacts(result)
  rescue
    _ -> %{}
  end
end
