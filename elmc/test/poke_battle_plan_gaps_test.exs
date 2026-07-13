defmodule Elmc.PokeBattlePlanGapsTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Plan.Lower.{Expr, Function, If}
  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.TestSupport.TemplateCompile

  @moduletag :slow

  setup do
    {:ok, result} =
      TemplateCompile.compile_watch_template("watchface_poke_battle",
        plan_ir_mode: :primary,
        plan_ir_strict: false,
        out_dir: Path.expand("tmp/poke_battle_plan_gaps", __DIR__)
      )

    decl_map = TemplateCompile.decl_map_from_result(result)
    {:ok, decl_map: decl_map, result: result}
  end

  defp plan_ctx(decl_map, decl) do
    Context.new(
      module: "Main",
      function_name: decl.name,
      decl_map: decl_map,
      params: decl.args,
      rc_required: true,
      fallible: true,
      function_tail: true
    )
  end

  defp plan_builder(decl) do
    b = Builder.new("Main", decl.name, args: decl.args, rc_required: true, fallible: true)

    Enum.reduce(Enum.with_index(decl.args), b, fn {name, idx}, acc ->
      {_reg, b1} = Builder.get_or_load_param(acc, idx, name)
      b1
    end)
  end

  test "withCustomName if branches compile", %{decl_map: decl_map} do
    decl = Map.fetch!(decl_map, {"Main", "withCustomName"})
    ctx = plan_ctx(decl_map, decl)
    b = plan_builder(decl)
    expr = decl.expr

    assert {:ok, _cond, _} = Expr.compile(expr.cond, ctx, b)
    assert {:ok, _then, _} = Expr.compile(expr.then_expr, ctx, b)
    assert {:ok, _else, _} = Expr.compile(expr.else_expr, ctx, b)
    assert {:ok, _reg, _} = If.compile(expr, ctx, b)
    assert {:ok, _plan} = Function.lower(decl, "Main", decl_map, rc_required: true)
  end

  test "playerLevelFromSteps lowers", %{decl_map: decl_map} do
    decl = Map.fetch!(decl_map, {"Main", "playerLevelFromSteps"})
    assert {:ok, _plan} = Function.lower(decl, "Main", decl_map, rc_required: true)
  end

  test "toggleDisplayOptions lowers", %{decl_map: decl_map} do
    decl = Map.fetch!(decl_map, {"Main", "toggleDisplayOptions"})
    assert {:ok, _plan} = Function.lower(decl, "Main", decl_map, rc_required: true)
  end

  test "playerForView lowers", %{decl_map: decl_map} do
    decl = Map.fetch!(decl_map, {"Main", "playerForView"})
    assert {:ok, _plan} = Function.lower(decl, "Main", decl_map, rc_required: true)
  end

  test "Render.dialog lowers", %{decl_map: decl_map} do
    decl = Map.fetch!(decl_map, {"Render", "dialog"})
    assert {:ok, plan} = Function.lower(decl, "Render", decl_map, rc_required: true)
    assert Enum.any?(plan.blocks, &(&1.id == 3))
  end
end
