defmodule Ide.Debugger.InitSurfaceEffectsContext do
  @moduledoc false

  alias Ide.Debugger.CompanionBridge.Runtime, as: CompanionBridgeRuntime
  alias Ide.Debugger.InitSurfaceEffects
  alias Ide.Debugger.ProtocolEvents
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.Types

  @type host :: %{
          required(:append_event) => (Types.runtime_state(),
                                      String.t(),
                                      Types.debugger_timeline_payload() ->
                                        Types.runtime_state()),
          required(:apply_step_once) => (Types.runtime_state(),
                                         Types.surface_target(),
                                         String.t(),
                                         Types.subscription_payload()
                                         | nil,
                                         String.t(),
                                         String.t() ->
                                           Types.runtime_state()),
          required(:apply_device_data_followups) => (Types.runtime_state(),
                                                     Types.surface_target(),
                                                     String.t(),
                                                     Types.app_model(),
                                                     String.t() ->
                                                       Types.runtime_state()),
          required(:apply_subscription_ok_response) => (Types.runtime_state(),
                                                        Types.surface_target(),
                                                        String.t(),
                                                        Types.subscription_payload(),
                                                        String.t(),
                                                        String.t() ->
                                                          Types.runtime_state()),
          required(:protocol_events_ctx) => (-> ProtocolEvents.ctx()),
          required(:protocol_rx_ctx) => (-> ProtocolRx.ctx()),
          required(:companion_bridge_ctx) => (-> CompanionBridgeRuntime.ctx()),
          required(:source_root_for_target) => (Types.surface_target() -> String.t())
        }

  @spec build(host()) :: InitSurfaceEffects.ctx()
  def build(host) when is_map(host), do: host
end
