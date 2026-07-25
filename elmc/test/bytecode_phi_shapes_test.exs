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

  test "native_int_phi mod_vars uses Elm modBy(modulus, value) order" do
    # modBy maxExclusive seed — lhs=modulus, rhs=value → rem(value, modulus)
    b = Builder.new("Main", "randomIndexLike", args: ["maxExclusive", "seed"])
    {mod_reg, b1} = Builder.get_or_load_param(b, 0, "maxExclusive")
    {seed_reg, b2} = Builder.get_or_load_param(b1, 1, "seed")
    {zero_reg, b3} = Builder.fresh_reg(b2)
    {cond_reg, b4} = Builder.fresh_reg(b3)
    {then_reg, b5} = Builder.fresh_reg(b4)
    {else_reg, b6} = Builder.fresh_reg(b5)
    {dest, b7} = Builder.fresh_reg(b6)

    {_, b8} =
      Builder.emit(b7, :const_int, %{
        dest: zero_reg,
        args: %{value: 0},
        effects: %{produces: {:owned, zero_reg}, consumes: [], borrows: [], fallible: false}
      })

    {_, b9} =
      Builder.emit(b8, :compare, %{
        dest: cond_reg,
        args: %{kind: :lte, left: mod_reg, right: zero_reg},
        effects: %{
          produces: {:owned, cond_reg},
          consumes: [],
          borrows: [mod_reg, zero_reg],
          fallible: false
        }
      })

    {_, b10} =
      Builder.emit(b9, :phi, %{
        dest: dest,
        args: %{
          then: then_reg,
          else: else_reg,
          cond: cond_reg,
          native_int_phi: true,
          then_shape: {:const_int, 0},
          else_shape: {:int_arith, %{kind: :mod_vars, lhs: mod_reg, rhs: seed_reg}},
          then_arm_block: 1,
          else_arm_block: 2
        },
        effects: %{produces: {:owned, dest}, consumes: [], borrows: [cond_reg], fallible: false}
      })

    plan = Builder.to_function_plan(Builder.emit_ret(b10, dest))
    section = Lower.lower(plan)

    assert {:ok, 3} = Runtime.run_section(section, params: [10, 3])
    assert {:ok, 0} = Runtime.run_section(section, params: [0, 3])
    assert {:ok, 1} = Runtime.run_section(section, params: [3, 10])
  end
end
