defmodule Ide.Debugger.SubscriptionPayloadTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.SubscriptionPayload

  test "attach prefers runtime message_value over simulator stub suffix" do
    state = %{
      watch: %{
        model: %{
          "active_subscriptions" => [
            %{
              "kind" => "cmd.subscription.register",
              "target" => "Pebble.Events.onMinuteChange",
              "message" => "MinuteChanged",
              "message_value" => %{"ctor" => "MinuteChanged", "args" => [17]}
            }
          ]
        }
      },
      simulator_settings: %{
        "use_simulated_time" => true,
        "simulated_date" => "2026-05-27",
        "simulated_time" => "08:53:00"
      }
    }

    assert SubscriptionPayload.attach(state, :watch, "MinuteChanged", "on_minute_change") ==
             "MinuteChanged 17"
  end

  test "attach keeps explicit payload in message text" do
    state = %{watch: %{model: %{"active_subscriptions" => []}}}

    assert SubscriptionPayload.attach(state, :watch, "MinuteChanged 42", "on_minute_change") ==
             "MinuteChanged 42"
  end
end
