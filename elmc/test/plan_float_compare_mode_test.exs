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

  test "ordering on untyped number vars selects int_boxed (not pointer)" do
    # elm-units Quantity.greaterThan binds polymorphic `number` payloads; pointer
    # i32.gt_s on Int handles is allocation order and infinite-loops Light.soft.
    b = Builder.new("Quantity", "greaterThan_lam_0", args: ["y", "x"], rc_required: false)
    {y_reg, b} = Builder.fresh_reg(b)
    {x_reg, b} = Builder.fresh_reg(b)

    ctx =
      Context.new(
        module: "Quantity",
        function_name: "greaterThan_lam_0",
        params: ["y", "x"],
        locals: %{"y" => y_reg, "x" => x_reg},
        local_types: %{}
      )

    assert {:ok, _reg, b2} =
             Compare.compile(
               %{
                 kind: :gt,
                 left: %{op: :var, name: "x"},
                 right: %{op: :var, name: "y"}
               },
               ctx,
               b
             )

    instrs =
      (b2.blocks ++ [b2.current_block])
      |> Enum.flat_map(& &1.instrs)

    compare = Enum.find(instrs, &match?(%{op: :compare}, &1))
    assert compare
    assert compare.args.mode == :int_boxed
  end
end
