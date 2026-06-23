defmodule Ide.Debugger.TickMessageResolutionTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.TickMessageResolution

  test "pick_subscription_message prefers minute ops for tick trigger" do
    {message, op} =
      TickMessageResolution.pick_subscription_message(
        ["HourChanged", "MinuteChanged"],
        ["onMinuteChange", "onHourChange"],
        "tick"
      )

    assert message == "MinuteChanged"
    assert op == "onMinuteChange"
  end

  test "tickish_message? matches clock-related constructors" do
    assert TickMessageResolution.tickish_message?("Tick")
    refute TickMessageResolution.tickish_message?("Save")
  end

  test "message_for_surface prefers runtime active subscription over introspect ops" do
    state = %{
      watch: %{
        model: %{
          "active_subscriptions" => [
            %{
              "kind" => "cmd.subscription.register",
              "target" => "Pebble.Events.onMinuteChange",
              "message" => "MinuteChanged"
            },
            %{
              "kind" => "cmd.subscription.register",
              "target" => "Pebble.Events.onHourChange",
              "message" => "HourChanged"
            }
          ]
        }
      }
    }

    message =
      TickMessageResolution.message_for_surface(state, :watch, %{
        introspect_for: fn _state, _target ->
          %{
            "msg_constructors" => ["HourChanged", "MinuteChanged"],
            "subscription_ops" => ["onHourChange", "onMinuteChange"]
          }
        end,
        attach_payload: fn _state, _target, msg, _trigger -> msg end
      })

    assert message == "MinuteChanged"
  end
end
