defmodule Elmx.SubscriptionsActiveSetTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Cmd
  alias Elmx.Runtime.Subscriptions.ActiveSet
  alias Elmx.Runtime.Values

  test "flattens register commands from sub batch manager value" do
    frame =
      Cmd.subscription_register("Pebble.Frame.every", interval_ms: 33, callback: :FrameTick)

    tap = Cmd.subscription_register("Pebble.Accel.onTap", callback: :Tap)

    active = ActiveSet.from_value(Values.sub_batch([frame, tap]))

    assert length(active) == 2
    assert Enum.any?(active, &(&1["target"] == "Pebble.Frame.every" and &1["message"] == "FrameTick"))
    assert Enum.any?(active, &(&1["target"] == "Pebble.Accel.onTap" and &1["message"] == "Tap"))
  end

  test "none and zero produce no active subscriptions" do
    assert ActiveSet.from_value(0) == []
    assert ActiveSet.from_value(nil) == []
  end
end
