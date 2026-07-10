defmodule Elmc.PlanVerifyTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.{Builder, EpilogueRelease, Types, Verify}
  alias Elmc.Backend.Plan.Types.FunctionPlan

  defp nested_maybe_good_plan do
    b =
      Builder.new("Main", "update", args: ["model", "msg"], rc_required: true, fallible: true)

    b = Builder.catch_begin(b)
    {from, b1} = Builder.emit_load_param(b, 0)
    {to, b2} = Builder.emit_load_param(b1, 1)
    {callee, b3} = Builder.fresh_reg(b2)

    {_, b4} =
      Builder.emit(b3, :call_fn, %{
        dest: callee,
        args: %{module: "Main", name: "lookupVector", args: [from, to]},
        effects: Types.fallible_effects(callee, [], [from, to])
      })

    {_, b5} =
      Builder.emit(b4, :maybe_is_nothing, %{
        args: %{reg: callee},
        effects: %{produces: nil, consumes: [], borrows: [callee], fallible: false}
      })

    b5a = Builder.emit_release(b5, callee)

    {_, b6} =
      Builder.emit(b5a, :publish, %{
        dest: :fn_out,
        args: %{},
        effects: Types.empty_effects()
      })

    b7 = Builder.catch_end(b6)
    b8 = Builder.emit_ret(b7, :fn_out)
    Builder.to_function_plan(b8)
  end

  defp leaked_plan do
    b = Builder.new("Main", "leak", args: [], rc_required: true)
    {reg1, b1} = Builder.emit_const_int(b, 1)
    {_reg2, b2} = Builder.emit_const_int(b1, 2)
    b3 = Builder.emit_ret(b2, reg1)
    Builder.to_function_plan(b3)
  end

  defp double_publish_plan do
    b =
      Builder.new("Main", "bad", args: [], rc_required: true)
      |> Builder.catch_begin()

    {_, b1} =
      Builder.emit(b, :publish, %{dest: :fn_out, args: %{}, effects: Types.empty_effects()})

    {_, b2} =
      Builder.emit(b1, :publish, %{dest: :fn_out, args: %{}, effects: Types.empty_effects()})

    b3 = Builder.catch_end(b2)
    b4 = Builder.emit_ret(b3, :fn_out)
    Builder.to_function_plan(b4)
  end

  test "companion send plan verifies — intermediates in scratch regs, single fn_out publish" do
    plan = Elmc.PlanFixtures.companion_send_plan()
    assert %FunctionPlan{rc_required: true} = plan
    assert :ok = Verify.run(plan)
    refute plan.blocks == []
  end

  test "nested maybe plan verifies — callee in owned reg before maybe inspect" do
    assert :ok = Verify.run(nested_maybe_good_plan())
  end

  test "rejects leaked owned register at function exit" do
    assert {:error, :leaked_owned_regs, _} = Verify.run(leaked_plan())
  end

  test "EpilogueRelease inserts plan release ops so ret blocks verify" do
    plan = leaked_plan() |> EpilogueRelease.run()
    assert :ok = Verify.run(plan)
    [%{instrs: instrs} | _] = plan.blocks
    assert Enum.any?(instrs, &(&1.op == :release))
  end

  test "rejects double fn_out publish" do
    assert {:error, :double_fn_out_publish, _} = Verify.run(double_publish_plan())
  end

  test "phi respects effects.consumes when cond local stays live after merge" do
    b = Builder.new("Main", "init", args: [], rc_required: true, fallible: true)

    {then_reg, b1} = Builder.emit_const_int(b, 1)
    {else_reg, b2} = Builder.emit_const_int(b1, 2)
    {cond_reg, b3} = Builder.emit_const_int(b2, 1)
    {merge_reg, b4} = Builder.fresh_reg(b3)

    {_, b5} =
      Builder.emit(b4, :phi, %{
        dest: merge_reg,
        args: %{then: then_reg, else: else_reg, cond: cond_reg},
        effects: %{
          produces: {:owned, merge_reg},
          consumes: [then_reg, else_reg],
          borrows: [],
          fallible: false
        }
      })

    {retained, b6} =
      Builder.emit(b5, :call_runtime, %{
        dest: merge_reg + 1,
        args: %{builtin: :retain, args: [cond_reg]},
        effects: %{
          produces: {:owned, merge_reg + 1},
          consumes: [],
          borrows: [cond_reg],
          fallible: false
        }
      })

    b7 = Builder.emit_release(b6, merge_reg)
    plan = b7 |> Builder.emit_ret(retained) |> Builder.to_function_plan()

    assert :ok = Verify.run(plan)
  end
end
