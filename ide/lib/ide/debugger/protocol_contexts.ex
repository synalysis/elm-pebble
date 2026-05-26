defmodule Ide.Debugger.ProtocolContexts do
  @moduledoc false

  alias Ide.Debugger.CmdCall
  alias Ide.Debugger.DeviceDataResponses
  alias Ide.Debugger.IntrospectAccess
  alias Ide.Debugger.ProtocolEvents
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.RuntimeModelMessages
  alias Ide.Debugger.StepExecution
  alias Ide.Debugger.Types

  @type events_host :: %{
          required(:introspect_for) => (Types.runtime_state(), Types.surface_target() -> map()),
          required(:simulator_settings_from_state) => (Types.runtime_state() -> map()),
          required(:session_key_from_state) => (Types.runtime_state() -> String.t() | nil),
          required(:surface_app_model) =>
            (Types.runtime_state(), Types.surface_target() -> Types.app_model())
        }

  @type rx_host :: %{
          required(:append_event) => (map(), String.t(), map() -> map()),
          required(:append_debugger_event) =>
            (map(), String.t(), Types.surface_target(), String.t(), String.t() -> map()),
          required(:append_runtime_exec_event_for_target) =>
            (map(), Types.surface_target(), map() -> map()),
          required(:source_root_for_target) => (Types.surface_target() -> String.t()),
          required(:introspect_for) => (map(), Types.surface_target() -> map()),
          required(:apply_step_once) =>
            (map(), Types.surface_target(), String.t(), Types.subscription_payload() | map() | nil,
             String.t(), String.t() -> map()),
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
          (Types.runtime_state(), Types.surface_target() -> map())
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
      runtime_source_loaded?: fn state, target ->
        state
        |> Map.get(target, %{})
        |> RuntimeArtifacts.shell_map()
        |> Map.get("elm_introspect")
        |> is_map()
      end
    }
  end

  @spec rx_apply_step_once(
          map(),
          Types.surface_target(),
          String.t(),
          Types.subscription_payload() | map() | nil,
          String.t(),
          String.t(),
          (map(), Types.surface_target(), String.t(), Types.subscription_payload() | map() | nil,
           String.t(), String.t() -> map())
        ) :: map()
  def rx_apply_step_once(st, target, message, message_value, source, trigger, apply_step_once)
      when is_function(apply_step_once, 6) do
    if is_map(message_value) do
      apply_step_once.(st, target, message, message_value, source, trigger)
    else
      apply_step_once.(st, target, message, nil, source, trigger)
    end
  end
end
