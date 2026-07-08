defmodule Elmc.PlanElmtrisCoverageTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Plan.PrimaryCoverage
  alias Elmc.TestSupport.TemplateCompile

  @moduletag :plan_surface
  @moduletag :slow

  @template "game_elmtris"

  test "game_elmtris Main reaches baseline plan lowering coverage" do
    assert {:ok, result} =
             TemplateCompile.compile_watch_template(@template, plan_ir_mode: :shadow)

    Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(result.ir))

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    report =
      result
      |> TemplateCompile.decl_map_from_result()
      |> PrimaryCoverage.main_functions_report(ir: result.ir)

    assert report.total == 44
    assert report.lowered == report.total,
           "expected all Main functions to lower, got #{report.lowered}/#{report.total}: #{inspect(Enum.take(report.failed, 8))}"
  end
end
