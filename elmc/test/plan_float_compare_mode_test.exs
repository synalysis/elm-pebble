defmodule Elmc.PlanFloatCompareModeTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.Compare

  test "Float == int literal selects float_boxed mode (not pointer)" do
    b = Builder.new("Test", "countdown_eq", args: ["stripIndex"], rc_required: false)
    {param_reg, b} = Builder.fresh_reg(b)

    ctx =
      Context.new(
        module: "Test",
        function_name: "countdown_eq",
        params: ["stripIndex"],
        locals: %{"stripIndex" => param_reg},
        local_types: %{"stripIndex" => "Float"}
      )

    assert {:ok, _reg, b2} =
             Compare.compile(
               %{
                 kind: :eq,
                 left: %{op: :var, name: "stripIndex"},
                 right: %{op: :int_literal, value: 0}
               },
               ctx,
               b
             )

    instrs =
      (b2.blocks ++ [b2.current_block])
      |> Enum.flat_map(& &1.instrs)

    compare = Enum.find(instrs, &match?(%{op: :compare}, &1))
    assert compare
    assert compare.args.mode == :float_boxed
  end

  test "Float < Float selects float_boxed mode" do
    b = Builder.new("Test", "float_lt", args: ["a", "b"], rc_required: false)
    {a_reg, b} = Builder.fresh_reg(b)
    {b_reg, b} = Builder.fresh_reg(b)

    ctx =
      Context.new(
        module: "Test",
        function_name: "float_lt",
        params: ["a", "b"],
        locals: %{"a" => a_reg, "b" => b_reg},
        local_types: %{"a" => "Float", "b" => "Float"}
      )

    assert {:ok, _reg, b2} =
             Compare.compile(
               %{
                 kind: :lt,
                 left: %{op: :var, name: "a"},
                 right: %{op: :var, name: "b"}
               },
               ctx,
               b
             )

    instrs =
      (b2.blocks ++ [b2.current_block])
      |> Enum.flat_map(& &1.instrs)

    compare = Enum.find(instrs, &match?(%{op: :compare}, &1))
    assert compare
    assert compare.args.mode == :float_boxed
  end
end
