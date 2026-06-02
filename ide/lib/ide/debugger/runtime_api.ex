defmodule Ide.Debugger.RuntimeApi do
  @moduledoc false

  alias Ide.Debugger.AgentSession
  alias Ide.Debugger.DebuggerStep
  alias Ide.Debugger.HotReloadSession
  alias Ide.Debugger.RuntimeBackgroundDrains
  alias Ide.Debugger.RuntimeExecutorConfig
  alias Ide.Debugger.RuntimePreview
  alias Ide.Debugger.Surface
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
      with {:ok, state} <-
             AgentSession.mutate(
               project_slug,
               &HotReloadSession.apply(&1, project_slug, attrs, hosts.hot_reload)
             ) do
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
