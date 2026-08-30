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

  test "Bool field == Bool field selects int_boxed (not pointer)" do
    # Scene3d.Transformation.compose: t1.isRightHanded == t2.isRightHanded.
    # Distinct True Int boxes must compare by value or modelScale.w becomes -1.
    b = Builder.new("Transformation", "compose", args: ["t1", "t2"], rc_required: false)
    {t1_reg, b} = Builder.fresh_reg(b)
    {t2_reg, b} = Builder.fresh_reg(b)

    ctx =
      Context.new(
        module: "Transformation",
        function_name: "compose",
        params: ["t1", "t2"],
        locals: %{"t1" => t1_reg, "t2" => t2_reg},
        local_types: %{}
      )

    assert {:ok, _reg, b2} =
             Compare.compile(
               %{
                 kind: :eq,
                 left: %{op: :field_access, arg: "t1", field: "isRightHanded"},
                 right: %{op: :field_access, arg: "t2", field: "isRightHanded"}
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

  test "Float mul tree > 0 selects float_boxed (not truncating int)" do
    # Frame3d.isRightHanded: triple product > 0. Untyped __mul__ trees must not
    # fall through to as_int (det in (0,1) would become 0 and fail the test).
    b = Builder.new("Frame3d", "isRightHanded", args: ["frame"], rc_required: false)
    {frame_reg, b} = Builder.fresh_reg(b)

    ctx =
      Context.new(
        module: "Frame3d",
        function_name: "isRightHanded",
        params: ["frame"],
        locals: %{"frame" => frame_reg},
        local_types: %{},
        decl_map: %{
          {"Direction3d", "xComponent"} => %{type: "Direction3d coordinates -> Float"}
        }
      )

    mul = fn a, b -> %{op: :call, name: "__mul__", args: [a, b]} end
    add = fn a, b -> %{op: :call, name: "__add__", args: [a, b]} end

    a = %{
      op: :qualified_call,
      target: "Direction3d.xComponent",
      args: [%{op: :field_access, arg: "frame", field: "xDirection"}]
    }

    e = %{
      op: :qualified_call,
      target: "Direction3d.xComponent",
      args: [%{op: :field_access, arg: "frame", field: "yDirection"}]
    }

    i = %{
      op: :qualified_call,
      target: "Direction3d.xComponent",
      args: [%{op: :field_access, arg: "frame", field: "zDirection"}]
    }

    left = add.(mul.(a, e), mul.(e, i))

    assert {:ok, _reg, b2} =
             Compare.compile(
               %{
                 kind: :gt,
                 left: left,
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

  test "abs of a Float difference < literal selects float_boxed" do
    b = Builder.new("Test", "near", args: ["got", "want"], rc_required: false)
    {got_reg, b} = Builder.fresh_reg(b)
    {want_reg, b} = Builder.fresh_reg(b)

    ctx =
      Context.new(
        module: "Test",
        function_name: "near",
        params: ["got", "want"],
        locals: %{"got" => got_reg, "want" => want_reg}
      )

    left = %{
      op: :call,
      name: "abs",
      args: [
        %{
          op: :call,
          name: "__sub__",
          args: [%{op: :var, name: "got"}, %{op: :var, name: "want"}]
        }
      ]
    }

    assert {:ok, _reg, b2} =
             Compare.compile(
               %{kind: :lt, left: left, right: %{op: :float_literal, value: 0.001}},
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
