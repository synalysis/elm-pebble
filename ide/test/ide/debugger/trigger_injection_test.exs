defmodule Ide.Debugger.TriggerInjectionTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.RuntimeSurfaces
  alias Ide.Debugger.TriggerInjection

  test "apply steps when subscription row is active" do
    state = %{
      running: true,
      watch: RuntimeSurfaces.default_watch(%{}),
      companion: RuntimeSurfaces.default_companion(),
      phone: RuntimeSurfaces.default_phone(),
      disabled_subscriptions: []
    }

    stepped =
      TriggerInjection.apply(
        state,
        :watch,
        %{trigger: "tick", message: "Tick"},
        %{
          source_root_for_target: fn :watch -> "watch" end,
          trigger_message_for_surface: fn _st, _target, _trigger, msg -> msg || "Tick" end,
          apply_step_once: fn _st, _target, message, _value, source, trigger ->
            %{stepped: true, message: message, source: source, trigger: trigger}
          end,
          append_event: fn st, _type, _payload -> st end
        }
      )

    assert stepped.stepped
    assert stepped.message == "Tick"
    assert stepped.source == "subscription_trigger"
  end

  test "apply appends blocked event when subscription is disabled" do
    state = %{
      running: true,
      watch: RuntimeSurfaces.default_watch(%{}),
      disabled_subscriptions: [%{"target" => "watch", "trigger" => "tick"}]
    }

    result =
      TriggerInjection.apply(
        state,
        :watch,
        %{trigger: "tick"},
        %{
          source_root_for_target: fn :watch -> "watch" end,
          trigger_message_for_surface: fn _st, _target, _trigger, _msg -> "Tick" end,
          apply_step_once: fn st, _, _, _, _, _ -> st end,
          append_event: fn _st, type, payload -> %{type: type, payload: payload} end
        }
      )

    assert result.type == "debugger.subscription_toggle"
    assert result.payload[:action] == "blocked"
  end
end
