defmodule Ide.Debugger.SubscriptionWireContexts do
  @moduledoc false

  alias Ide.Debugger.AutoFireRuntime
  alias Ide.Debugger.SubscriptionTriggerWire
  alias Ide.Debugger.TriggerMessageSurface
  alias Ide.Debugger.Types

  @type trigger_wire_host :: %{
          required(:introspect_for) => (map(), Types.surface_target() -> map()),
          required(:normalize_target) => (Types.wire_input() -> Types.surface_target())
        }

  @type tick_resolution_host :: %{
          required(:introspect_for) => (map(), Types.surface_target() -> map()),
          required(:attach_payload) =>
            (map(), Types.surface_target(), String.t(), String.t() -> String.t())
        }

  @type payload_host :: %{
          optional(:introspect) => (map(), Types.surface_target() -> map()),
          optional(:settings) => (map() -> map()),
          optional(:introspect_for) => (map(), Types.surface_target() -> map()),
          optional(:simulator_settings) => (map() -> map())
        }

  @type auto_fire_host :: %{
          required(:trigger_candidates) =>
            (Types.runtime_state(), Types.surface_target() -> [Types.trigger_candidate()]),
          required(:trigger_message) =>
            (Types.runtime_state(), Types.surface_target(), String.t(), String.t() | nil -> String.t()),
          required(:apply_step) =>
            (Types.runtime_state(), Types.surface_target(), String.t(), map() | nil, String.t(), String.t() ->
               Types.runtime_state()),
          required(:subscription_row_enabled?) =>
            (Types.runtime_state(), Types.surface_target(), map() -> boolean()),
          required(:auto_fire_row_enabled?) =>
            (Types.runtime_state(), Types.surface_target(), map() -> boolean()),
          required(:simulator_now) =>
            (Types.runtime_state(), Types.surface_target() -> NaiveDateTime.t()),
          required(:source_root_for_target) => (Types.surface_target() -> String.t()),
          optional(:default_interval_ms) => pos_integer()
        }

  @spec trigger_wire(trigger_wire_host()) :: SubscriptionTriggerWire.injection_modal_ctx()
  def trigger_wire(host) when is_map(host), do: host

  @spec tick_resolution(tick_resolution_host()) :: TriggerMessageSurface.resolve_ctx()
  def tick_resolution(host) when is_map(host), do: host

  @spec payload(payload_host()) :: TriggerMessageSurface.payload_ctx()
  def payload(host) when is_map(host) do
    %{
      introspect: host[:introspect] || host[:introspect_for],
      settings: host[:settings] || host[:simulator_settings]
    }
  end

  @spec auto_fire(auto_fire_host()) :: AutoFireRuntime.apply_ctx()
  def auto_fire(host) when is_map(host), do: host
end
