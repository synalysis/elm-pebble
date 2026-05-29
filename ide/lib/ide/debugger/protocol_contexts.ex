defmodule Ide.Debugger.ProtocolContexts do
  @moduledoc false

  alias Ide.Debugger.CmdCall
  alias Ide.Debugger.DeviceDataResponses
  alias Ide.Debugger.IntrospectAccess
  alias Ide.Debugger.ProtocolEvents
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.RuntimeModelMessages
  alias Ide.Debugger.StepExecution
  alias Ide.Debugger.Types

  @type events_host :: %{
          required(:introspect_for) =>
            (Types.runtime_state(), Types.surface_target() -> Types.elm_introspect()),
          required(:simulator_settings_from_state) =>
            (Types.runtime_state() -> Types.simulator_settings()),
          required(:session_key_from_state) => (Types.runtime_state() -> String.t() | nil),
          required(:surface_app_model) =>
            (Types.runtime_state(), Types.surface_target() -> Types.app_model())
        }

  @type rx_host :: %{
          required(:append_event) =>
            (Types.runtime_state(), String.t(), Types.debugger_timeline_payload() ->
               Types.runtime_state()),
          required(:append_debugger_event) =>
            (Types.runtime_state(), String.t(), Types.surface_target(), String.t(), String.t() ->
               Types.runtime_state()),
          required(:append_runtime_exec_event_for_target) =>
            (Types.runtime_state(), Types.surface_target(), Types.debugger_timeline_payload() ->
               Types.runtime_state()),
          required(:source_root_for_target) => (Types.surface_target() -> String.t()),
          required(:introspect_for) =>
            (Types.runtime_state(), Types.surface_target() -> Types.elm_introspect()),
          required(:apply_step_once) =>
            (Types.runtime_state(), Types.surface_target(), String.t(),
             Types.subscription_payload() | nil, String.t(), String.t() -> Types.runtime_state()),
          required(:protocol_events_ctx) => (-> ProtocolEvents.ctx())
        }

  @spec events_ctx(events_host()) :: ProtocolEvents.ctx()
  def events_ctx(host) when is_map(host) do
    %{
      cmd_calls_for_message: fn state, target, message ->
        cmd_calls_for_message(state, target, message, host.introspect_for)
      end,
      simulator_settings_from_state: host.simulator_settings_from_state,
      session_key_from_state: host.session_key_from_state,
      surface_app_model: host.surface_app_model
    }
  end

  @spec cmd_calls_for_message(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          (Types.runtime_state(), Types.surface_target() -> Types.elm_introspect())
        ) :: [Types.cmd_call()]
  def cmd_calls_for_message(state, target, message, introspect_for)
      when is_map(state) and is_binary(message) and is_function(introspect_for, 2) do
    ctor = RuntimeModelMessages.wire_constructor(message)
    ei = introspect_for.(state, target)

    ei
    |> IntrospectAccess.cmd_calls("update_cmd_calls")
    |> DeviceDataResponses.filter_update_cmd_calls(ctor)
    |> CmdCall.expand_helpers(ei)
  end

  @spec rx_ctx(rx_host()) :: ProtocolRx.ctx()
  def rx_ctx(host) when is_map(host) do
    %{
      append_event: host.append_event,
      append_debugger_event: host.append_debugger_event,
      append_runtime_exec_event_for_target: host.append_runtime_exec_event_for_target,
      source_root_for_target: host.source_root_for_target,
      introspect_for: host.introspect_for,
      introspect_cmd_calls: &IntrospectAccess.cmd_calls/2,
      apply_step_once: fn st, target, message, message_value, source, trigger ->
        rx_apply_step_once(st, target, message, message_value, source, trigger, host.apply_step_once)
      end,
      refresh_runtime_fingerprints: &StepExecution.refresh_runtime_fingerprints/3,
      protocol_events_ctx: host.protocol_events_ctx,
      runtime_ready_for_delivery?: &ProtocolRx.runtime_ready_for_delivery?/2
    }
  end

  @spec rx_apply_step_once(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          Types.subscription_payload() | nil,
          String.t(),
          String.t(),
          (Types.runtime_state(), Types.surface_target(), String.t(),
           Types.subscription_payload() | nil, String.t(), String.t() -> Types.runtime_state())
        ) :: Types.runtime_state()
  def rx_apply_step_once(st, target, message, message_value, source, trigger, apply_step_once)
      when is_function(apply_step_once, 6) do
    if is_map(message_value) do
      apply_step_once.(st, target, message, message_value, source, trigger)
    else
      apply_step_once.(st, target, message, nil, source, trigger)
    end
  end
end
