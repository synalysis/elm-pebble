defmodule Ide.Debugger.SimulatorWatchDeliveryContext do
  @moduledoc false

  alias Ide.Debugger.ProtocolEvents
  alias Ide.Debugger.SimulatorWatchDelivery
  alias Ide.Debugger.Types

  @type host :: %{
          required(:apply_step_once) => (Types.runtime_state(),
                                         Types.surface_target(),
                                         String.t(),
                                         Types.subscription_payload()
                                         | map()
                                         | nil,
                                         String.t(),
                                         String.t() ->
                                           Types.runtime_state()),
          required(:trigger_candidates) => (Types.runtime_state(), Types.surface_target() ->
                                              [Types.trigger_candidate()]),
          required(:model_active?) => (Types.runtime_state(), Types.surface_target(), map() ->
                                         boolean()),
          required(:trigger_message_for_surface) => (Types.runtime_state(),
                                                     Types.surface_target(),
                                                     String.t(),
                                                     String.t()
                                                     | nil ->
                                                       String.t()),
          required(:simulator_settings) => (Types.runtime_state() -> map()),
          required(:protocol_events_ctx) => (-> ProtocolEvents.ctx())
        }

  @spec build(host()) :: SimulatorWatchDelivery.apply_ctx()
  def build(host) when is_map(host) do
    %{
      apply_step_once: host.apply_step_once,
      trigger_candidates: host.trigger_candidates,
      model_active?: host.model_active?,
      trigger_message_for_surface: host.trigger_message_for_surface,
      simulator_settings: host.simulator_settings,
      protocol_events_ctx: host.protocol_events_ctx,
      protocol_supports_weather?: fn state ->
        SimulatorWatchDelivery.protocol_supports_weather?(state, host.protocol_events_ctx)
      end
    }
  end
end
