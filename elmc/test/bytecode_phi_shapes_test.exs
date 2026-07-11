defmodule Elmc.BytecodePhiShapesTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Bytecode.{Lower, Runtime}
  alias Elmc.Backend.Plan.Builder

  test "truthy_native phi arms evaluate compare and const shapes" do
    b = Builder.new("Main", "andChain", args: ["x"])
    {x_reg, b1} = Builder.get_or_load_param(b, 0, "x")
    {cond_reg, b2} = Builder.fresh_reg(b1)
    {then_reg, b3} = Builder.fresh_reg(b2)
    {else_reg, b4} = Builder.fresh_reg(b3)
    {dest, b5} = Builder.fresh_reg(b4)

    {_, b6} =
      Builder.emit(b5, :compare, %{
        dest: cond_reg,
        args: %{kind: :gt, left: x_reg, right: then_reg},
        effects: %{produces: {:owned, cond_reg}, consumes: [], borrows: [x_reg], fallible: false}
      })

    {_, b7} =
      Builder.emit(b6, :phi, %{
        dest: dest,
        args: %{
          then: then_reg,
          else: else_reg,
          cond: cond_reg,
          truthy_native: true,
          then_shape: {:const_int, 1},
          else_shape: {:const_int, 0},
          then_arm_block: 1,
          else_arm_block: 2
        },
        effects: %{produces: {:owned, dest}, consumes: [], borrows: [cond_reg], fallible: false}
      })

    plan = Builder.to_function_plan(Builder.emit_ret(b7, dest))
    section = Lower.lower(plan)

    assert {:ok, 1} = Runtime.run_section(section, params: [3])
    assert {:ok, 0} = Runtime.run_section(section, params: [0])
  end
end
