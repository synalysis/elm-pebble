defmodule Elmx.SubscriptionCmdsTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.{Cmd, Followups, Pebble}

  test "frame_every runtime dispatch emits subscription register cmd" do
    cmd = Pebble.runtime_dispatch("elmx_frame_every", [33, :FrameTick])

    assert %{"kind" => "cmd.subscription.register", "target" => "Pebble.Frame.every"} = cmd
    assert cmd["interval_ms"] == 33
    assert cmd["message"] == "FrameTick"
  end

  test "vibes runtime dispatch emits effect cmd" do
    cmd = Pebble.runtime_dispatch("elmx_vibes_short_pulse", [])

    assert %{"kind" => "cmd.effect.vibes", "variant" => "short_pulse"} = cmd
  end

  test "platform application and watchface runtime dispatch emit platform effect cmds" do
    assert %{"kind" => "cmd.effect.platform", "variant" => "application"} =
             Pebble.runtime_dispatch("elmx_platform_application", [])

    assert %{"kind" => "cmd.effect.platform", "variant" => "watchface"} =
             Pebble.runtime_dispatch("elmx_platform_watchface", [])
  end

  test "subscription register produces subscription_command followup row" do
    cmd = Cmd.subscription_register("Pebble.Accel.onTap", callback: :Tap)

    assert [%{"source" => "subscription_command", "message" => "Tap"}] =
             Followups.from_commands(cmd)
  end
end
