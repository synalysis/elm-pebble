defmodule Ide.Debugger.CompanionBridgeContext do
  @moduledoc false

  alias Ide.Debugger.CmdCall
  alias Ide.Debugger.CompanionBridge.Runtime, as: CompanionBridgeRuntime
  alias Ide.Debugger.CompanionBridgeRequest
  alias Ide.Debugger.DeviceDataResponses
  alias Ide.Debugger.IntrospectAccess
  alias Ide.Debugger.RuntimeModelMessages
  alias Ide.Debugger.Types

  @type host :: %{
          required(:introspect_for) => (Types.runtime_state(), Types.surface_target() ->
                                          Types.elm_introspect()),
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
          required(:deliver_weather_to_watch) => (Types.runtime_state() ->
                                                    Types.runtime_state()),
          required(:settings) => (Types.runtime_state() -> Types.runtime_state())
        }

  @spec build(host()) :: CompanionBridgeRuntime.ctx()
  def build(host) when is_map(host) do
    introspect_for = host.introspect_for

    %{
      introspect: introspect_for,
      cmd_calls: &IntrospectAccess.cmd_calls/2,
      bridge_requests_from_init: fn state, target ->
        ei = introspect_for.(state, target)

        ei
        |> IntrospectAccess.cmd_calls("init_cmd_calls")
        |> CmdCall.expand_helpers(ei)
        |> CompanionBridgeRequest.from_cmd_calls()
      end,
      bridge_requests_from_update: fn state, target, message ->
        current_ctor = RuntimeModelMessages.wire_constructor(message)
        ei = introspect_for.(state, target)

        ei
        |> IntrospectAccess.cmd_calls("update_cmd_calls")
        |> DeviceDataResponses.filter_update_cmd_calls(current_ctor)
        |> CmdCall.expand_helpers(ei)
        |> CompanionBridgeRequest.from_cmd_calls()
      end,
      append_event: host.append_event,
      apply_step: host.apply_step_once,
      deliver_weather_to_watch: host.deliver_weather_to_watch,
      settings: host.settings
    }
  end
end
