defmodule Elmc.Backend.CCodegen.OperatorCallRewriteTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.Bool, as: NativeBool
  alias Elmc.Backend.CCodegen.SpecialValues.Core

  test "operator_call_rewrite does not identity-rewrite kernel operator calls" do
    left = %{op: :int_literal, value: 1}
    right = %{op: :int_literal, value: 2}

    assert Core.operator_call_rewrite("__sub__", [left, right]) == nil
    assert Core.operator_call_rewrite("__add__", [left, right]) == nil
  end

  test "operator_call_rewrite still lowers Basics operator names" do
    left = %{op: :int_literal, value: 1}
    right = %{op: :int_literal, value: 2}

    assert Core.operator_call_rewrite("Basics.sub", [left, right]) ==
             %{op: :call, name: "__sub__", args: [left, right]}
  end

  test "native bool normalization terminates on kernel arithmetic calls" do
    expr = %{
      op: :call,
      name: "__sub__",
      args: [
        %{op: :int_literal, value: 3},
        %{op: :int_literal, value: 1}
      ]
    }

    assert NativeBool.expr?(expr, %{}) == false
    assert Host.special_value_from_target("__sub__", expr.args) == nil
  end
end
