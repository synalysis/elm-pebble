defmodule Elmx.SubscriptionsFrameTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Pebble.Subscriptions
  alias Elmx.Runtime.Pebble.Subscriptions.Frame

  test "frame mask encodes interval in high bits" do
    assert Frame.mask([%{op: :int_literal, value: 16}, %{op: :var, name: "msg"}]) ==
             8192 + Bitwise.bsl(16, 16)
  end

  test "frame fps mask uses derived interval" do
    assert Frame.fps_mask([%{op: :int_literal, value: 30}, %{op: :var, name: "msg"}]) ==
             8192 + Bitwise.bsl(div(1000, 30), 16)
  end

  test "batch OR includes frame and accel tap subscriptions" do
    items = [
      %{op: :qualified_call, target: "Time.every", args: [%{op: :int_literal, value: 1000}, :msg]},
      %{op: :qualified_call, target: "Pebble.Frame.every", args: [%{op: :int_literal, value: 33}, :msg]},
      %{op: :qualified_call, target: "Pebble.Accel.onTap", args: [:msg]}
    ]

    mask = Subscriptions.batch_mask(items)
    assert Bitwise.band(mask, 16) == 16
    assert Bitwise.band(mask, 8192) == 8192
  end
end
