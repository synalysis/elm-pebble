defmodule Ide.Debugger.ConfigurationApi do
  @moduledoc false

  alias Ide.Debugger.AgentSession
  alias Ide.Debugger.ConfigurationReload
  alias Ide.Debugger.ConfigurationSession
  alias Ide.Debugger.Types

  @type runtime_state :: Types.RuntimeState.t() | Types.RuntimeState.wire_map()

  @spec save_configuration(String.t(), Types.save_configuration_attrs()) :: {:ok, runtime_state()}
  def save_configuration(project_slug, values) when is_binary(project_slug) and is_map(values) do
    AgentSession.with_hosts(fn hosts ->
      AgentSession.mutate(
        project_slug,
        &ConfigurationSession.save(&1, project_slug, values, hosts.configuration_session)
      )
    end)
  end

  @spec reload_configuration(String.t()) :: {:ok, runtime_state()}
  def reload_configuration(project_slug) when is_binary(project_slug) do
    AgentSession.with_hosts(fn hosts ->
      AgentSession.mutate(
        project_slug,
        &ConfigurationReload.apply(&1, project_slug, hosts.configuration_reload)
      )
    end)
  end
end
