defmodule Ide.Debugger.SubscriptionCommandFollowupTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.PackageCommandHandler
  alias Ide.Debugger.RuntimeFollowups

  test "PackageCommandHandler handles subscription_command follow-up rows" do
    row = %{
      "source" => "subscription_command",
      "message" => "FrameTick",
      "package" => "elm-pebble/elm-watch",
      "command" => %{
        "kind" => "cmd.subscription.register",
        "target" => "Pebble.Frame.every",
        "interval_ms" => 33,
        "message" => "FrameTick"
      }
    }

    assert {:handled, _state, event_payload, %{message: "FrameTick"}} =
             PackageCommandHandler.handle(%{}, "watch", "elm-pebble/elm-watch", row)

    assert event_payload.response_message == "FrameTick"
    assert event_payload.command.target == "Pebble.Frame.every"
    assert event_payload.command.interval_ms == 33
  end

  test "RuntimeFollowups applies subscription_command via package handler" do
    steps = :ets.new(:subscription_steps, [:set, :private])

    ctx = %{
      append_event: fn st, _type, _payload -> st end,
      apply_step_once: fn st, target, message, value, source, trigger ->
        :ets.insert(steps, {target, message, value, source, trigger})
        st
      end,
      track_http_command: fn st, _cmd -> st end,
      source_root_for_target: fn :watch -> "watch" end
    }

    state = %{
      watch: %{
        model: %{
          "runtime_model" => %{"pageIndex" => 0}
        }
      }
    }

    followups = [
      %{
        "source" => "subscription_command",
        "message" => "FrameTick",
        "package" => "elm-pebble/elm-watch",
        "command" => %{
          "kind" => "cmd.subscription.register",
          "target" => "Pebble.Frame.every",
          "interval_ms" => 33,
          "message" => "FrameTick"
        }
      }
    ]

    RuntimeFollowups.apply_after_step(
      state,
      :watch,
      "init",
      "init",
      followups,
      ctx
    )

    assert [{:watch, "FrameTick", _value, "runtime_followup", "runtime_followup"}] =
             :ets.tab2list(steps)
  end
end
