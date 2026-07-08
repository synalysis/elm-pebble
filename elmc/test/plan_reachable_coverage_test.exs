defmodule Elmc.PlanReachableCoverageTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Plan.PrimaryCoverage
  alias Elmc.TestSupport.TemplateCompile

  @moduletag :plan_surface
  @moduletag :slow

  @templates ~w(
    game_elmtris
    game_2048
    watchface_analog
    watchface_digital
    watchface_yes
    app_minimal
    game_tiny_bird
  )

  for template <- @templates do
    @tag template: template
    test "reachable plan coverage for #{template}", %{template: template} do
      assert {:ok, result} =
               TemplateCompile.compile_watch_template(template, plan_ir_mode: :primary)

      Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(result.ir))

      on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

      decl_map = TemplateCompile.decl_map_from_result(result)

      reachable =
        PrimaryCoverage.reachable_report(decl_map, ir: result.ir, entry_module: "Main")

      assert reachable.total > 0

      assert reachable.lowered == reachable.total,
             "#{template} reachable #{reachable.lowered}/#{reachable.total}: #{inspect(Enum.take(reachable.failed, 8))}"
    end
  end

  test "watchface_yes Yes modules lower completely" do
    assert {:ok, result} =
             TemplateCompile.compile_watch_template("watchface_yes", plan_ir_mode: :primary)

    Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(result.ir))

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl_map = TemplateCompile.decl_map_from_result(result)
    yes_report = PrimaryCoverage.module_prefix_report(decl_map, "Yes.", ir: result.ir)

    assert yes_report.total == 21
    assert yes_report.lowered == yes_report.total
  end
end
