defmodule Elmx.SubscriptionBatchDynamicTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Pebble.SpecialValues.Helpers
  alias Elmx.Runtime.Pebble.Subscriptions

  test "static batch stays a folded mask literal" do
    items = [
      %{
        op: :qualified_call,
        target: "Pebble.Button.onPress",
        args: [
          %{value: 2, op: :int_literal, union_ctor: "Pebble.Button.Up"},
          %{value: 1, op: :int_literal, union_ctor: "UpPressed"}
        ]
      },
      %{op: :qualified_call, target: "Pebble.Compass.onChange", args: [:msg]}
    ]

    assert Subscriptions.static_batch?(items)

    list = %{op: :list_literal, items: items}

    assert {:ok, %{op: :int_literal, value: mask}} =
             Helpers.subscription_batch([list])

    assert mask == Subscriptions.batch_mask(items)
    assert mask > 0
  end

  test "batch with a let-bound sub uses runtime sub_batch" do
    items = [
      %{
        op: :qualified_call,
        target: "Pebble.Button.onPress",
        args: [
          %{value: 2, op: :int_literal, union_ctor: "Pebble.Button.Up"},
          %{value: 1, op: :int_literal, union_ctor: "UpPressed"}
        ]
      },
      %{name: "frameSub", op: :var}
    ]

    refute Subscriptions.static_batch?(items)

    list = %{op: :list_literal, items: items}

    assert {:ok, %{op: :runtime_call, function: "elmx_sub_batch", args: [^list]}} =
             Helpers.subscription_batch([list])
  end
end
