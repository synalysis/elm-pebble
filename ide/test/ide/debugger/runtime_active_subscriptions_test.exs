defmodule Ide.Debugger.RuntimeActiveSubscriptionsTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.RuntimeActiveSubscriptions
  alias Ide.Debugger.SubscriptionActivation

  test "model_active? uses runtime active_subscriptions when present" do
    active = [
      %{
        "kind" => "cmd.subscription.register",
        "target" => "Pebble.Frame.every",
        "message" => "FrameTick",
        "interval_ms" => 33
      }
    ]

    state = %{
      watch: %{
        model: %{
          "runtime_model" => %{"alive" => true},
          "active_subscriptions" => active
        }
      }
    }

    row = %{trigger: "Pebble.Frame.every", message: "FrameTick", target: "watch"}

    assert SubscriptionActivation.model_active?(state, :watch, row)
  end

  test "triggers_equivalent matches phone_to_watch gateway aliases" do
    assert RuntimeActiveSubscriptions.triggers_equivalent?("phone_to_watch", "on_phone_to_watch")
    assert RuntimeActiveSubscriptions.triggers_equivalent?("watch_to_phone", "on_watch_to_phone")
    refute RuntimeActiveSubscriptions.triggers_equivalent?("phone_to_watch", "on_watch_to_phone")
  end

  test "empty active_subscriptions still allows fallback catalog triggers" do
    state = %{
      watch: %{
        model: %{
          "runtime_model" => %{"n" => 0},
          "active_subscriptions" => [],
          "debugger_contract" => %{"subscription_calls" => []}
        }
      }
    }

    row = %{trigger: "button_up", message: "ButtonPressed", target: "watch"}

    assert SubscriptionActivation.model_active?(state, :watch, row)
  end

  test "empty active_subscriptions marks row inactive even when guards would pass" do
    state = %{
      watch: %{
        model: %{
          "runtime_model" => %{"alive" => true},
          "active_subscriptions" => [],
          "debugger_contract" => %{
            "subscription_calls" => [
              %{
                "target" => "Pebble.Frame.every",
                "callback_constructor" => "FrameTick",
                "activation_guards" => [
                  %{"kind" => "field_truthy", "subject" => "model.alive"}
                ]
              }
            ]
          }
        }
      }
    }

    row = %{trigger: "Pebble.Frame.every", message: "FrameTick", target: "watch"}

    refute SubscriptionActivation.model_active?(state, :watch, row)
  end

  test "empty active_subscriptions allows unguarded catalog subscriptions" do
    state = %{
      watch: %{
        shell: %{
          "debugger_contract" => %{
            "subscription_calls" => [
              %{
                "target" => "Pebble.Speaker.onFinished",
                "name" => "onFinished",
                "event_kind" => "on_finished",
                "callback_constructor" => "SpeakerFinished"
              }
            ]
          }
        },
        model: %{
          "runtime_model" => %{},
          "active_subscriptions" => []
        }
      }
    }

    row = %{trigger: "on_finished", message: "SpeakerFinished", target: "watch"}

    assert SubscriptionActivation.model_active?(state, :watch, row)
  end

  test "match_for_row returns runtime register command" do
    active = [
      %{
        "kind" => "cmd.subscription.register",
        "target" => "Pebble.Speaker.onFinished",
        "message" => "SpeakerFinished",
        "message_value" => %{"ctor" => "SpeakerFinished", "args" => ["FinishedDone"]}
      }
    ]

    state = %{watch: %{model: %{"active_subscriptions" => active}}}
    row = %{trigger: "on_finished", message: "SpeakerFinished", target: "watch"}

    assert %{"target" => "Pebble.Speaker.onFinished"} =
             RuntimeActiveSubscriptions.match_for_row(state, :watch, row)
  end

  test "trigger_candidates builds rows from active subscriptions with catalog labels" do
    active = [
      %{
        "kind" => "cmd.subscription.register",
        "target" => "Pebble.Events.onMinuteChange",
        "message" => "MinuteChanged",
        "message_value" => %{"ctor" => "MinuteChanged", "args" => [5]}
      }
    ]

    ei = %{
      "subscription_calls" => [
        %{
          "target" => "Pebble.Events.onMinuteChange",
          "name" => "onMinuteChange",
          "label" => "Minute change",
          "callback_constructor" => "MinuteChanged"
        }
      ]
    }

    state = %{watch: %{model: %{"active_subscriptions" => active}}}

    [row] =
      RuntimeActiveSubscriptions.trigger_candidates(
        state,
        :watch,
        ei,
        "watch",
        fn _ -> true end
      )

    assert row.trigger == "on_minute_change"
    assert row.message == "MinuteChanged"
    assert row.label == "Minute change"
    assert row.model_active == true
  end

  test "trigger_candidates matches catalog metadata per button callback in batch" do
    active = [
      %{"target" => "Pebble.Button.onPress", "message" => "LeftPressed"},
      %{"target" => "Pebble.Button.onPress", "message" => "UpPressed"},
      %{"target" => "Pebble.Button.onPress", "message" => "DownPressed"},
      %{"target" => "Pebble.Button.onPress", "message" => "RightPressed"}
    ]

    ei = %{
      "subscription_calls" => [
        %{
          "target" => "Pebble.Button.onPress",
          "name" => "onPress",
          "callback_constructor" => "LeftPressed",
          "arg_snippets" => ["Button.Back"]
        },
        %{
          "target" => "Pebble.Button.onPress",
          "name" => "onPress",
          "callback_constructor" => "UpPressed",
          "arg_snippets" => ["Button.Up"]
        },
        %{
          "target" => "Pebble.Button.onPress",
          "name" => "onPress",
          "callback_constructor" => "DownPressed",
          "arg_snippets" => ["Button.Down"]
        },
        %{
          "target" => "Pebble.Button.onPress",
          "name" => "onPress",
          "callback_constructor" => "RightPressed",
          "arg_snippets" => ["Button.Select"]
        }
      ]
    }

    state = %{watch: %{model: %{"active_subscriptions" => active}}}

    rows =
      RuntimeActiveSubscriptions.trigger_candidates(
        state,
        :watch,
        ei,
        "watch",
        fn _ -> true end
      )

    left = Enum.find(rows, &(&1.message == "LeftPressed"))
    assert left.button == "back"
    assert Enum.any?(rows, &(&1.message == "UpPressed" and &1.button == "up"))
    assert Enum.any?(rows, &(&1.message == "DownPressed" and &1.button == "down"))
    assert Enum.any?(rows, &(&1.message == "RightPressed" and &1.button == "select"))
  end
end
