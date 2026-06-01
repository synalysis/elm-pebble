defmodule Ide.Debugger.RuntimeHostCallbacks do
  @moduledoc false

  alias Ide.Debugger.AutoFireRuntime
  alias Ide.Debugger.RuntimeHost
  alias Ide.Debugger.SubscriptionActivation
  alias Ide.Debugger.SubscriptionAutoFireState
  alias Ide.Debugger.Types

  @type append_event_fn :: (Types.runtime_state(), String.t(), map() -> Types.runtime_state())

  @type append_debugger_event_fn ::
          (Types.runtime_state(), String.t(), Types.surface_target(), String.t(), String.t() ->
             Types.runtime_state())

  @type apply_step_once_fn ::
          (Types.runtime_state(), Types.surface_target(), String.t(), Types.subscription_payload() | nil,
           String.t(), String.t() -> Types.runtime_state())

  @type source_root_fn :: (Types.surface_target() -> String.t())

  @type deps :: %{
          required(:append_event) => append_event_fn(),
          required(:append_debugger_event) => append_debugger_event_fn(),
          required(:apply_step_once) => apply_step_once_fn(),
          required(:apply_step_without_value) =>
            (Types.runtime_state(), Types.surface_target(), String.t(), String.t(), String.t() ->
               Types.runtime_state()),
          required(:source_root_for_target) => source_root_fn(),
          required(:session_key_from_state) => (Types.runtime_state() -> String.t() | nil),
          required(:simulator_settings_from_state) => (Types.runtime_state() -> Types.simulator_settings()),
          required(:introspect_for) =>
            (Types.runtime_state(), Types.surface_target() -> Types.elm_introspect() | map()),
          required(:surface_app_model) =>
            (Types.runtime_state(), Types.surface_target() -> Types.app_model()),
          required(:normalize_step_target) => (Types.wire_input() -> Types.surface_target()),
          required(:trigger_message_for_surface) =>
            (Types.runtime_state(), Types.surface_target(), String.t(), String.t() | nil -> String.t()),
          required(:attach_subscription_payload) =>
            (Types.runtime_state(), Types.surface_target(), String.t(), String.t() -> String.t()),
          required(:merge_runtime_artifacts) =>
            (Types.runtime_state(), Types.surface_target(), map() -> Types.runtime_state()),
          required(:apply_subscription_ok_response) =>
            (Types.runtime_state(), Types.surface_target(), String.t(), map(), String.t(), String.t() ->
               Types.runtime_state()),
          required(:maybe_attach_compile_artifacts) =>
            (Types.runtime_state(), Types.surface_target(), map() -> Types.runtime_state()),
          required(:maybe_append_runtime_status) =>
            (Types.runtime_state(), Types.surface_target() -> Types.runtime_state()),
          required(:maybe_append_runtime_status_after_init) =>
            (Types.runtime_state(), Types.surface_target(), map(), Types.elm_introspect() | map() ->
               Types.runtime_state()),
          required(:maybe_append_contract) =>
            (Types.runtime_state(), map() | nil -> Types.runtime_state()),
          required(:maybe_append_runtime_exec) => (Types.runtime_state(), String.t() -> Types.runtime_state()),
          required(:maybe_append_phone_view_render) =>
            (Types.runtime_state(), String.t() -> Types.runtime_state()),
          required(:append_runtime_exec) =>
            (Types.runtime_state(), Types.surface_target(), map() -> Types.runtime_state()),
          required(:simulator_now) =>
            (Types.runtime_state(), Types.surface_target() -> NaiveDateTime.t()),
          required(:default_auto_fire_interval_ms) => pos_integer()
        }

  @spec build(deps()) :: RuntimeHost.callbacks()
  def build(deps) when is_map(deps) do
    %{
      append_event: deps.append_event,
      append_debugger_event: deps.append_debugger_event,
      apply_step_once: deps.apply_step_once,
      apply_step_without_value: deps.apply_step_without_value,
      source_root_for_target: deps.source_root_for_target,
      session_key_from_state: deps.session_key_from_state,
      simulator_settings_from_state: deps.simulator_settings_from_state,
      introspect_for: deps.introspect_for,
      surface_app_model: deps.surface_app_model,
      normalize_step_target: deps.normalize_step_target,
      trigger_message_for_surface: deps.trigger_message_for_surface,
      attach_subscription_payload: deps.attach_subscription_payload,
      merge_runtime_artifacts: deps.merge_runtime_artifacts,
      apply_subscription_ok_response: deps.apply_subscription_ok_response,
      maybe_attach_compile_artifacts: deps.maybe_attach_compile_artifacts,
      maybe_append_runtime_status: deps.maybe_append_runtime_status,
      maybe_append_runtime_status_after_init: deps.maybe_append_runtime_status_after_init,
      maybe_append_contract: deps.maybe_append_contract,
      maybe_append_runtime_exec: deps.maybe_append_runtime_exec,
      maybe_append_phone_view_render: deps.maybe_append_phone_view_render,
      append_runtime_exec: deps.append_runtime_exec,
      model_active?: &SubscriptionActivation.model_active?/3,
      subscription_row_enabled?: fn state, target, row ->
        AutoFireRuntime.subscription_row_enabled?(
          state,
          target,
          row,
          deps.source_root_for_target
        )
      end,
      auto_fire_row_enabled?: fn state, target, row ->
        SubscriptionAutoFireState.auto_fire_subscription_enabled?(
          state,
          target,
          row,
          deps.source_root_for_target
        )
      end,
      simulator_now: deps.simulator_now,
      default_auto_fire_interval_ms: deps.default_auto_fire_interval_ms
    }
  end
end
