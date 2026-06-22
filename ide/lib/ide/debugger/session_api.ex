defmodule Ide.Debugger.SessionApi do
  @moduledoc false

  alias Ide.Debugger.AgentSession
  alias Ide.Debugger.AgentStore
  alias Ide.Debugger.AutoTickWorkers
  alias Ide.Debugger.RuntimeBackgroundDrains
  alias Ide.Debugger.SessionStartReset
  alias Ide.Debugger.SettingsApi
  alias Ide.Debugger.Types
  alias Ide.Debugger.WatchProfileApply

  @type runtime_state :: Types.RuntimeState.t() | Types.RuntimeState.wire_map()

  @spec start_session(String.t()) :: {:ok, runtime_state()}
  def start_session(project_slug) when is_binary(project_slug),
    do: start_session(project_slug, %{})

  @spec start_session(String.t(), Types.session_attrs()) :: {:ok, runtime_state()}
  def start_session(project_slug, attrs) when is_binary(project_slug) and is_map(attrs) do
    AgentSession.with_hosts(fn hosts ->
      AgentSession.mutate(
        project_slug,
        &SessionStartReset.start(&1, project_slug, attrs, hosts.lifecycle)
      )
    end)
  end

  @spec reset(String.t()) :: {:ok, runtime_state()}
  def reset(project_slug) when is_binary(project_slug) do
    AgentSession.with_hosts(fn hosts ->
      AgentSession.mutate(
        project_slug,
        &SessionStartReset.reset(&1, project_slug, hosts.lifecycle)
      )
    end)
  end

  @spec forget_project(String.t()) :: :ok
  def forget_project(project_slug) when is_binary(project_slug) do
    AgentStore.forget(project_slug, on_remove: &AutoTickWorkers.stop_worker/1)
  end

  @spec set_watch_profile(String.t(), Types.session_attrs()) :: {:ok, runtime_state()}
  def set_watch_profile(project_slug, attrs \\ %{})
      when is_binary(project_slug) and is_map(attrs) do
    AgentSession.with_hosts(fn hosts ->
      AgentSession.mutate(project_slug, &WatchProfileApply.apply(&1, attrs, hosts.watch_profile))
    end)
  end

  @spec set_simulator_settings(String.t(), Types.simulator_settings()) :: {:ok, runtime_state()}
  def set_simulator_settings(project_slug, attrs \\ %{})
      when is_binary(project_slug) and is_map(attrs) do
    settings = SettingsApi.normalize(attrs)

    AgentSession.with_hosts(fn hosts ->
      AgentSession.mutate(
        project_slug,
        &SettingsApi.apply_to_state(&1, settings, hosts.simulator_settings)
      )
      |> case do
        {:ok, state} ->
          RuntimeBackgroundDrains.schedule_all(project_slug, state)
          {:ok, state}

        other ->
          other
      end
    end)
  end
end
