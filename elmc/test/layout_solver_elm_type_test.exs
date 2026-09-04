defmodule Elmc.LayoutSolverElmTypeTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.LayoutSolver
  alias Elmc.Backend.CCodegen.StoragePlan
  alias ElmEx.Typesys.Type

  test "expr_plan prefers List Int elm_type over untyped heuristics" do
    expr = %{op: :var, name: "xs", elm_type: Type.list(Type.int())}
    plan = LayoutSolver.expr_plan(expr, %{})
    assert plan == StoragePlan.int_compact()
  end

  test "expr_plan prefers List Float elm_type" do
    expr = %{op: :var, name: "ys", elm_type: Type.list(Type.float())}
    plan = LayoutSolver.expr_plan(expr, %{})
    assert plan == StoragePlan.float_compact()
  end
end
