defmodule Elmc.PlanListCaseLowerTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower
  alias Elmc.TestSupport.TemplateCompile

  @moduletag :plan_surface

  test "lowers list cons/empty case in game_tiny_bird step recycled binding" do
    assert {:ok, result} =
             TemplateCompile.compile_watch_template("game_tiny_bird", plan_ir_mode: :primary)

    Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(result.ir))
    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl_map = TemplateCompile.decl_map_from_result(result)
    step = Map.fetch!(decl_map, {"Main", "step"})
    recycled_case = find_recycled_case(step.expr)

    mini_decl = %{
      name: "recycledCase",
      args: ["movedTubes", "model"],
      type: "List Main.Tube -> List Main.Tube",
      expr: recycled_case,
      ownership: [:borrow_arg, :retain_result]
    }

    assert match?(
             {:ok, _},
             PlanLower.lower(mini_decl, "Main", decl_map, rc_required: true)
           )
  end

  defp find_recycled_case(%{op: :let_in, name: "recycled", value_expr: value}), do: value

  defp find_recycled_case(%{op: :let_in, in_expr: rest}), do: find_recycled_case(rest)
  defp find_recycled_case(_), do: nil
end
