defmodule Elmc.PlanReachableCoverageTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Plan.PrimaryCoverage
  alias Elmc.TestSupport.{HostSmoke, PlanStrictTemplates, StrictCompileAssertions, TemplateCompile}

  @moduletag :plan_surface
  @moduletag :slow

  # Filtered by `ELMC_HOST_SMOKE_TEMPLATE` for `mix-test-per-template.sh`.
  for template <- HostSmoke.templates(PlanStrictTemplates.names()) do
    @tag template: template

    test "strict reachable plan coverage for #{template}", %{template: template} do
      result = StrictCompileAssertions.compile_template!(template)
      out_dir = StrictCompileAssertions.artifact_dir(template)

      StrictCompileAssertions.assert_strict_compile!(result, out_dir,
        typecheck: false,
        rc_shape: true,
        reachable: true
      )
    end
  end

  test "watchface_yes Yes modules lower completely under strict primary" do
    assert {:ok, result} =
             TemplateCompile.compile_watch_template("watchface_yes",
               plan_ir_mode: :primary,
               plan_ir_strict: true
             )

    Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(result.ir))

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl_map = TemplateCompile.decl_map_from_result(result)
    yes_report = PrimaryCoverage.module_prefix_report(decl_map, "Yes.", ir: result.ir)

    assert yes_report.total == 25
    assert yes_report.lowered == yes_report.total
  end
end
