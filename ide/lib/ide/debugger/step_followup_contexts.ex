defmodule Ide.Debugger.StepFollowupContexts do
  @moduledoc false

  alias Ide.Debugger.DeviceDataResponses
  alias Ide.Debugger.GeolocationResponses
  alias Ide.Debugger.RuntimeFollowups
  alias Ide.Debugger.SubscriptionResponses
  alias Ide.Debugger.Types

  @type host :: %{
          required(:append_event) =>
            (Types.runtime_state(), String.t(), Types.debugger_timeline_payload() ->
               Types.runtime_state()),
          required(:source_root_for_target) => (Types.surface_target() -> String.t()),
          required(:apply_step_without_value) =>
            (Types.runtime_state(), Types.surface_target(), String.t(), String.t(), String.t() ->
               Types.runtime_state()),
          required(:apply_step_with_value) =>
            (Types.runtime_state(), Types.surface_target(), String.t(),
             Types.subscription_payload() | nil, String.t(), String.t() -> Types.runtime_state()),
          optional(:introspect_for) =>
            (Types.runtime_state(), Types.surface_target() -> Types.elm_introspect()),
          optional(:simulator_settings) => (Types.runtime_state() -> Types.simulator_settings()),
          optional(:track_http_command) =>
            (Types.runtime_state(), Types.tracked_http_command() -> Types.runtime_state()),
          optional(:append_debugger_event) =>
            (Types.runtime_state(), String.t(), Types.surface_target(), String.t(), String.t() | nil,
             Types.timeline_step_message_value() -> Types.runtime_state())
        }

  @spec device_data(host()) :: DeviceDataResponses.apply_ctx()
  def device_data(host) when is_map(host) do
    %{
      append_event: host.append_event,
      apply_step_once: host.apply_step_with_value,
      source_root_for_target: host.source_root_for_target
    }
  end

  @spec runtime_followups(host()) :: RuntimeFollowups.apply_ctx()
  def runtime_followups(host) when is_map(host) do
    %{
      append_event: host.append_event,
      append_debugger_event: host[:append_debugger_event] || fn st, _, _, _, _, _ -> st end,
      apply_step_once: host.apply_step_with_value,
      source_root_for_target: host.source_root_for_target,
      track_http_command: host[:track_http_command] || fn st, _cmd -> st end,
      simulator_settings: host[:simulator_settings] || fn _st -> %{} end
    }
  end

  @spec geolocation(host()) :: GeolocationResponses.apply_ctx()
  def geolocation(host) when is_map(host) do
    %{
      introspect_for: host[:introspect_for] || fn _st, _t -> %{} end,
      append_event: host.append_event,
      apply_step_once: host.apply_step_with_value,
      source_root_for_target: host.source_root_for_target
    }
  end

  @spec subscription_responses(host()) :: SubscriptionResponses.apply_ctx()
  def subscription_responses(host) when is_map(host) do
    %{apply_step_once: host.apply_step_with_value}
  end
end
