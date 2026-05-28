defmodule Ide.Debugger.StepFollowupContexts do
  @moduledoc false

  alias Ide.Debugger.DeviceDataResponses
  alias Ide.Debugger.GeolocationResponses
  alias Ide.Debugger.RuntimeFollowups
  alias Ide.Debugger.SubscriptionResponses
  alias Ide.Debugger.Types

  @type host :: %{
          required(:append_event) => (map(), String.t(), map() -> map()),
          required(:source_root_for_target) => (Types.surface_target() -> String.t()),
          required(:apply_step_without_value) =>
            (map(), Types.surface_target(), String.t(), String.t(), String.t() -> map()),
          required(:apply_step_with_value) =>
            (map(), Types.surface_target(), String.t(), Types.subscription_payload() | map() | nil,
             String.t(), String.t() -> map()),
          optional(:introspect_for) => (map(), Types.surface_target() -> map()),
          optional(:simulator_settings) => (map() -> map()),
          optional(:track_http_command) => (map(), map() -> map())
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
