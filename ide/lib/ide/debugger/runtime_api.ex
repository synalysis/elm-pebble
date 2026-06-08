defmodule Ide.Debugger.RuntimeApi do
  @moduledoc false

  alias Ide.Debugger.AgentSession
  alias Ide.Debugger.DebuggerContractSnapshot
  alias Ide.Debugger.DebuggerStep
  alias Ide.Debugger.HotReloadSession
  alias Ide.Debugger.RuntimeBackgroundDrains
  alias Ide.Debugger.RuntimeExecutorConfig
  alias Ide.Debugger.RuntimePreview
  alias Ide.Debugger.Surface
  alias Ide.Debugger.SurfaceCompileArtifacts
  alias Ide.Debugger.SurfaceTargets
  alias Ide.Debugger.Types

  @type runtime_state :: Types.RuntimeState.t() | Types.RuntimeState.wire_map()

  @spec render_runtime_preview_for_debugger(
          Surface.surface_map() | nil,
          Surface.surface_map() | nil,
          Types.surface_target()
        ) :: Surface.surface_map() | nil
  def render_runtime_preview_for_debugger(snapshot_runtime, latest_runtime, target) do
    RuntimePreview.render_for_debugger_entry(
      snapshot_runtime,
      latest_runtime,
      target,
      RuntimeExecutorConfig.module()
    )
  end

  @spec reload(String.t(), Types.reload_attrs()) :: {:ok, runtime_state()}
  def reload(project_slug, attrs \\ %{}) when is_binary(project_slug) and is_map(attrs) do
    AgentSession.with_hosts(fn hosts ->
      rel_path = Map.get(attrs, :rel_path) || Map.get(attrs, "rel_path")
      source = Map.get(attrs, :source) || Map.get(attrs, "source") || ""
      source_root = SurfaceTargets.normalize_source_root(attrs)

      precompiled =
        if DebuggerContractSnapshot.elm_introspect?(rel_path, source, source_root) do
          SurfaceCompileArtifacts.precompile_inline_artifacts(
            project_slug,
            source,
            rel_path,
            source_root
          )
        else
          %{}
        end

      with {:ok, state} <-
             AgentSession.mutate(project_slug, fn state ->
               state =
                 if is_map(precompiled) and map_size(precompiled) > 0 do
                   Map.put(state, :__reload_precompiled_artifacts__, %{
                     source_root: source_root,
                     artifacts: precompiled
                   })
                 else
                   state
                 end

               state
               |> HotReloadSession.apply(project_slug, attrs, hosts.hot_reload)
               |> Map.delete(:__reload_precompiled_artifacts__)
             end) do
        RuntimeBackgroundDrains.schedule_all(project_slug, state)
        {:ok, state}
      end
    end)
  end

  @spec step(String.t(), Types.step_attrs()) :: {:ok, runtime_state()}
  def step(project_slug, attrs \\ %{}) when is_binary(project_slug) and is_map(attrs) do
    AgentSession.with_hosts(fn hosts ->
      with {:ok, state} <-
             AgentSession.mutate(project_slug, &DebuggerStep.apply(&1, attrs, hosts.step)) do
        RuntimeBackgroundDrains.schedule_all(project_slug, state)
        {:ok, state}
      end
    end)
  end
end
