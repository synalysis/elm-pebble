defmodule Elmc.MaybeWithDefaultPickSlotTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.MaybeWithDefaultPickSlot

  test "try_emit recognizes Maybe.withDefault defaultCtor (pickSlot model slotsFn)" do
    expr = %{
      op: :qualified_call,
      target: "Maybe.withDefault",
      args: [
        %{op: :int_literal, value: 2, union_ctor: "SunCorner"},
        %{
          op: :qualified_call,
          target: "Main.pickSlot",
          args: [%{op: :var, name: "model"}, %{op: :qualified_call, target: "Main.bottomRightSlots", args: [%{op: :var, name: "model"}]}]
        }
      ]
    }

    decl_map = %{
      {"Main", "pickBottomRight"} => %{name: "pickBottomRight", args: ["model"], expr: expr},
      {"Main", "pickSlot"} => %{name: "pickSlot", args: ["model", "slots"], expr: %{op: :int_literal, value: 0}},
      {"Main", "bottomRightSlots"} => %{name: "bottomRightSlots", args: ["model"], expr: %{op: :int_literal, value: 0}}
    }

    Process.put(:elmc_constructor_tags, %{"SunCorner" => 2})

    assert {:ok, body, _callees, :rc_native} =
             MaybeWithDefaultPickSlot.try_emit("Main", "pickBottomRight", expr, decl_map)

    assert body =~ "elmc_maybe_with_default_int(2"
    assert body =~ "elmc_fn_Main_pickSlot"
    assert body =~ "elmc_fn_Main_bottomRightSlots"
  end

  test "try_emit recognizes case pickSlot of Just x -> x; Nothing -> default" do
    expr = %{
      op: :case,
      subject: %{
        op: :qualified_call,
        target: "Corner.pickSlot",
        args: [%{op: :var, name: "model"}, %{op: :qualified_call, target: "Corner.slots", args: [%{op: :var, name: "model"}]}]
      },
      branches: [
        %{pattern: %{kind: :constructor, name: "Just", tag: 0}, expr: %{op: :var, name: "model"}},
        %{pattern: %{kind: :constructor, name: "Nothing", tag: 1}, expr: %{op: :int_literal, value: 0, union_ctor: "Fallback"}}
      ]
    }

    decl_map = %{
      {"Corner", "pickCorner"} => %{name: "pickCorner", args: ["model"], expr: expr}
    }

    Process.put(:elmc_constructor_tags, %{"Fallback" => 9})

    assert {:ok, body, _, :rc_native} =
             MaybeWithDefaultPickSlot.try_emit("Corner", "pickCorner", expr, decl_map)

    assert body =~ "elmc_maybe_with_default_int(9"
    assert body =~ "elmc_fn_Corner_pickSlot"
  end
end
