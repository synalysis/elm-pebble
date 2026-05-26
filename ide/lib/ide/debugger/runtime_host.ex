defmodule Ide.Debugger.RuntimeHost do
  @moduledoc false

  alias Ide.Debugger.RuntimeContexts
  alias Ide.Debugger.Types

  @type append_event_fn :: (Types.runtime_state(), String.t(), map() -> Types.runtime_state())

  @type append_debugger_event_fn ::
          (Types.runtime_state(), String.t(), Types.surface_target(), String.t(), String.t() ->
             Types.runtime_state())

  @type apply_step_once_fn ::
          (Types.runtime_state(), Types.surface_target(), String.t(), Types.subscription_payload() | map() | nil,
           String.t(), String.t() -> Types.runtime_state())

  @type apply_step_without_value_fn ::
          (Types.runtime_state(), Types.surface_target(), String.t(), String.t(), String.t() ->
             Types.runtime_state())

  @type callbacks :: %{
          required(:append_event) => append_event_fn(),
          required(:append_debugger_event) => append_debugger_event_fn(),
          required(:apply_step_once) => apply_step_once_fn(),
          required(:apply_step_without_value) => apply_step_without_value_fn(),
          required(:source_root_for_target) => (Types.surface_target() -> String.t()),
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
          required(:maybe_append_elm_introspect) => (Types.runtime_state(), map() | nil -> Types.runtime_state()),
          required(:maybe_append_runtime_exec) => (Types.runtime_state(), String.t() -> Types.runtime_state()),
          required(:maybe_append_phone_view_render) => (Types.runtime_state(), String.t() -> Types.runtime_state()),
          required(:append_runtime_exec) =>
            (Types.runtime_state(), Types.surface_target(), map() -> Types.runtime_state()),
          required(:model_active?) =>
            (Types.runtime_state(), Types.surface_target(), map() -> boolean()),
          required(:subscription_row_enabled?) =>
            (Types.runtime_state(), Types.surface_target(), map() -> boolean()),
          required(:auto_fire_row_enabled?) =>
            (Types.runtime_state(), Types.surface_target(), map() -> boolean()),
          required(:simulator_now) =>
            (Types.runtime_state(), Types.surface_target() -> NaiveDateTime.t()),
          optional(:default_auto_fire_interval_ms) => pos_integer()
        }

  @spec build(callbacks()) :: RuntimeContexts.host()
  def build(callbacks) when is_map(callbacks), do: callbacks
end
