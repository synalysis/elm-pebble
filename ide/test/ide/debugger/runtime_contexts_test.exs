defmodule Ide.Debugger.RuntimeContextsTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.RuntimeContexts
  alias Ide.Debugger.RuntimeSurfaces
  alias Ide.Debugger.TriggerSurface

  defp minimal_host(overrides \\ %{}) do
    Map.merge(
      %{
        append_event: fn st, _type, _payload -> st end,
        append_debugger_event: fn st, _kind, _target, _message, _source -> st end,
        apply_step_once: fn st, _target, _message, _value, _source, _trigger -> st end,
        apply_step_without_value: fn st, _target, _message, _source, _trigger -> st end,
        source_root_for_target: fn target -> to_string(target) end,
        session_key_from_state: fn _st -> nil end,
        simulator_settings_from_state: fn _st -> %{} end,
        introspect_for: fn _st, _target -> %{} end,
        surface_app_model: fn _st, _target -> %{} end,
        normalize_message_value: fn _st, _target, value, _model -> value end,
        normalize_step_target: fn value -> value end,
        trigger_message_for_surface: fn _st, _target, _trigger, _msg -> "Tick" end,
        attach_subscription_payload: fn _st, _target, message, _trigger -> message end,
        merge_runtime_artifacts: fn st, _target, _fields -> st end,
        apply_subscription_ok_response: fn st, _target, _cb, _payload, _source, _trigger -> st end,
        maybe_attach_compile_artifacts: fn st, _target, _ei -> st end,
        maybe_append_runtime_status: fn st, _target -> st end,
        maybe_append_runtime_status_after_init: fn st, _target, _exec, _intro -> st end,
        maybe_append_elm_introspect: fn st, _payload -> st end,
        maybe_append_runtime_exec: fn st, _root -> st end,
        maybe_append_phone_view_render: fn st, _root -> st end,
        append_runtime_exec: fn st, _target, _extra -> st end,
        trigger_candidates: fn _st, _target -> [] end,
        model_active?: fn _st, _target, _row -> true end,
        subscription_row_enabled?: fn _st, _target, _row -> true end,
        auto_fire_row_enabled?: fn _st, _target, _row -> true end,
        simulator_now: fn _st, _target -> ~N[2020-01-01 12:00:00] end
      },
      overrides
    )
  end

  test "build returns wired context bundle" do
    ctx = RuntimeContexts.build(minimal_host())

    assert is_map(ctx.step_apply)
    assert is_map(ctx.protocol_events)
    assert is_map(ctx.protocol_rx)
    assert is_map(ctx.companion_bridge)
    assert is_map(ctx.init_surface_effects)
    assert is_function(ctx.trigger_wire.introspect_for, 2)
  end

  test "hot_reload_context delegates merge and reload events" do
    ctx = RuntimeContexts.build(minimal_host())

    hot_reload_ctx =
      RuntimeContexts.hot_reload_context(ctx, "Main.elm", "module Main exposing (..)", "watch")

    assert is_function(hot_reload_ctx.merge_introspect, 1)
    assert is_function(hot_reload_ctx.append_reload_events, 6)
  end

  test "trigger_surface ctx lists candidates for running watch state" do
    ctx = RuntimeContexts.build(minimal_host())

    state =
      RuntimeSurfaces.default_watch(%{})
      |> then(fn watch -> %{running: true, watch: watch, companion: %{}, phone: %{}} end)

    assert is_list(TriggerSurface.candidates(state, :watch, ctx.trigger_surface))
  end
end
