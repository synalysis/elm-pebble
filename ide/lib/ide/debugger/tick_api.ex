defmodule Ide.Debugger.TickApi do
  @moduledoc false

  alias Ide.Debugger.AgentSession
  alias Ide.Debugger.TickIngress
  alias Ide.Debugger.Types

  @type runtime_state :: Types.RuntimeState.t() | Types.RuntimeState.wire_map()

  @spec tick(String.t(), Types.step_attrs()) :: {:ok, runtime_state()}
  def tick(project_slug, attrs \\ %{}) when is_binary(project_slug) and is_map(attrs) do
    AgentSession.with_hosts(fn hosts ->
      AgentSession.mutate(project_slug, &TickIngress.tick(&1, attrs, hosts.tick_ingress))
    end)
  end

  @spec start_auto_tick(String.t(), Types.step_attrs()) :: {:ok, runtime_state()}
  def start_auto_tick(project_slug, attrs \\ %{}) when is_binary(project_slug) and is_map(attrs) do
    AgentSession.with_hosts(fn hosts ->
      AgentSession.mutate(project_slug, &TickIngress.start_auto_tick(&1, project_slug, attrs, hosts.tick_ingress))
    end)
  end

  @spec stop_auto_tick(String.t()) :: {:ok, runtime_state()}
  def stop_auto_tick(project_slug) when is_binary(project_slug) do
    AgentSession.with_hosts(fn hosts ->
      AgentSession.mutate(project_slug, &TickIngress.stop_auto_tick(&1, hosts.append_event))
    end)
  end

  @spec set_auto_fire(String.t(), Types.step_attrs()) :: {:ok, runtime_state()}
  def set_auto_fire(project_slug, attrs \\ %{}) when is_binary(project_slug) and is_map(attrs) do
    AgentSession.with_hosts(fn hosts ->
      AgentSession.mutate(project_slug, &TickIngress.set_auto_fire(&1, project_slug, attrs, hosts.tick_ingress))
    end)
  end
end
