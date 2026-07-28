defmodule Elmc.Backend.CCodegen.ExprSubstituteVarsTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.Expr

  test "substitute_expr expands sub_vars and mul_vars like add_vars" do
    diameter = %{op: :int_literal, value: 144}
    top_band = %{op: :call, name: "__idiv__", args: [diameter, %{op: :int_literal, value: 6}]}
    gap = %{op: :int_literal, value: 3}

    substitutions = %{
      "diameter" => diameter,
      "topBand" => top_band,
      "gap" => gap
    }

    subbed =
      Expr.substitute_expr(%{op: :sub_vars, left: "diameter", right: "topBand"}, substitutions)

    assert %{op: :call, name: "__sub__", args: [left, right]} = subbed
    assert left == diameter
    assert right == top_band

    mulled = Expr.substitute_expr(%{op: :mul_vars, left: "gap", right: "gap"}, substitutions)

    assert %{
             op: :call,
             name: "__mul__",
             args: [^gap, ^gap]
           } = mulled

    added = Expr.substitute_expr(%{op: :add_vars, left: "gap", right: "diameter"}, substitutions)

    assert %{
             op: :call,
             name: "__add__",
             args: [^gap, ^diameter]
           } = added
  end

  test "substitute_expr resolves nested let bindings through sub_vars chains" do
    substitutions = %{
      "panelWidth" => %{op: :int_literal, value: 144},
      "boardWidth" => %{op: :int_literal, value: 114},
      "diff" => %{op: :sub_vars, left: "panelWidth", right: "boardWidth"}
    }

    centered =
      Expr.substitute_expr(
        %{
          op: :call,
          name: "__idiv__",
          args: [%{op: :var, name: "diff"}, %{op: :int_literal, value: 2}]
        },
        substitutions
      )

    assert %{
             op: :call,
             name: "__idiv__",
             args: [
               %{
                 op: :call,
                 name: "__sub__",
                 args: [
                   %{op: :int_literal, value: 144},
                   %{op: :int_literal, value: 114}
                 ]
               },
               %{op: :int_literal, value: 2}
             ]
           } = centered
  end
end
