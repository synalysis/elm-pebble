defmodule Elmc.PlanEmptyVarTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Plan.Lower.{Case, Expr, Function}
  alias Elmc.Backend.Plan.Lower.Case.ListSwitch
  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.TestSupport.TemplateCompile

  @moduletag :slow

  test "compile_empty_var lowers synthetic [] / var case" do
    branches = [
      %{
        pattern: %{kind: :constructor, name: "[]", resolved_name: "[]"},
        expr: %{op: :list_literal, items: []}
      },
      %{
        pattern: %{kind: :var, name: "xs"},
        expr: %{op: :var, name: "xs"}
      }
    ]

    assert ListSwitch.empty_var_branches?(branches)

    ctx =
      Context.new(
        module: "Main",
        function_name: "test",
        decl_map: %{},
        params: ["subject"],
        rc_required: true,
        fallible: true,
        function_tail: true
      )

    b = Builder.new("Main", "test", args: ["subject"], rc_required: true, fallible: true)
    {_reg, b0} = Builder.get_or_load_param(b, 0, "subject")

    assert {:ok, _reg, _b} =
             ListSwitch.compile_empty_var(
               %{op: :var, name: "subject"},
               branches,
               ctx,
               b0
             )

    case_expr = %{op: :case, subject: "subject", branches: branches}
    assert {:ok, _reg, _b} = Case.compile(case_expr, ctx, b0)
  end

  test "downloadedPieces case uses empty_var branches" do
    {:ok, result} =
      TemplateCompile.compile_watch_template("watchface_tangram_time",
        plan_ir_mode: :primary,
        plan_ir_strict: false,
        out_dir: Path.expand("tmp/plan_empty_var", __DIR__)
      )

    decl_map = TemplateCompile.decl_map_from_result(result)
    {bindings, body} = peel_lets(Map.fetch!(decl_map, {"Main", "tangramFaceOps"}).expr)

    assert body.target == "List.concat"
    assert length(body.args) == 1

    ctx =
      Context.new(
        module: "Main",
        function_name: "tangramFaceOps",
        decl_map: decl_map,
        params: ["model"],
        rc_required: true,
        fallible: true,
        function_tail: true
      )

    b = Builder.new("Main", "tangramFaceOps", args: ["model"], rc_required: true, fallible: true)
    {_reg, b0} = Builder.get_or_load_param(b, 0, "model")

    {ctx1, b1} =
      Enum.reduce(bindings, {ctx, b0}, fn {name, val}, {c, bb} ->
        assert {:ok, reg, b2} = Expr.compile(val, Context.for_branch_arm(c), bb)
        {Context.put_local(c, name, reg), Builder.bind_local(b2, name, reg)}
      end)

    [lists] = body.args
    pieces_segment = Enum.at(lists.items, 2)

    assert ListSwitch.empty_var_branches?(pieces_segment.in_expr.branches)
    assert {:ok, _reg, _b} = Expr.compile(pieces_segment, ctx1, b1)
    assert {:ok, _reg, _b} = Expr.compile(body, ctx1, b1)

    decl = Map.fetch!(decl_map, {"Main", "tangramFaceOps"})
    assert {:ok, _plan} = Function.lower(decl, "Main", decl_map, rc_required: true)
  end

  defp peel_lets(expr, acc \\ [])

  defp peel_lets(%{op: :let_in, name: name, value_expr: value, in_expr: inner}, acc) do
    peel_lets(inner, [{name, value} | acc])
  end

  defp peel_lets(other, acc), do: {Enum.reverse(acc), other}
end
