defmodule Ide.Debugger.TriggerQueries do
  @moduledoc false

  alias Ide.Debugger.AgentHosts
  alias Ide.Debugger.SubscriptionApi
  alias Ide.Debugger.TriggerDiscovery
  alias Ide.Debugger.Types

  @type trigger_attrs :: Types.available_triggers_attrs()

  @spec candidates(Types.runtime_state() | map(), :watch | :companion | :phone | nil, AgentHosts.t()) ::
          [Types.trigger_candidate()]
  def candidates(state, target, %AgentHosts{} = hosts) do
    TriggerDiscovery.candidates(state, target, hosts.trigger_discovery)
  end

  @spec normalize_optional_target(trigger_attrs()) :: Types.surface_target() | nil
  def normalize_optional_target(attrs) when is_map(attrs) do
    TriggerDiscovery.normalize_optional_target(Map.get(attrs, :target) || Map.get(attrs, "target"))
  end

  @spec injection_modal_supported?(Types.runtime_state(), map(), AgentHosts.t()) :: boolean()
  def injection_modal_supported?(state, row, hosts),
    do: SubscriptionApi.injection_modal_supported?(state, row, hosts.hub)
end
