defmodule Elmc.WasmCfgLowerTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Plan.Lower.Function, as: PlanFn
  alias Elmc.Backend.Wasm.Lower.Function, as: WasmFn

  test "if/merge plan lowers to valid wasm state-switch CFG" do
    decl = %{
      name: "pick",
      args: ["flag"],
      expr: %{
        op: :if,
        cond: %{op: :var, name: "flag"},
        then_expr: %{op: :int_literal, value: 1},
        else_expr: %{op: :int_literal, value: 2}
      }
    }

    assert {:ok, plan} = PlanFn.lower(decl, "Main", %{}, rc_required: true)

    body = WasmFn.lower(plan).body

    assert body =~ "(local $plan_state i32)"
    assert body =~ "$plan_loop"
    assert body =~ "$plan_switch_done"
    assert body =~ "(i32.const 1)"
    assert body =~ "(i32.const 2)"
    refute body =~ "(block $block_3)"

    # if/else arms finish with :none and must fall through to the merge block,
    # not exit the state switch early.
    assert body =~ "(local.set $plan_state (i32.const 3))"
    assert length(Regex.scan(~r/local\.set \$plan_state \(i32\.const -1\)/, body)) == 1
  end
end
