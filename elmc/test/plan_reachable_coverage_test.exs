defmodule Elmc.PlanReachableCoverageTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Plan.PrimaryCoverage
  alias Elmc.TestSupport.{PlanStrictTemplates, TemplateCompile}

  @moduletag :plan_surface
  @moduletag :slow

  for template <- PlanStrictTemplates.names() do
    @tag template: template

    test "strict reachable plan coverage for #{template}", %{template: template} do
      out_dir = Path.expand("tmp/plan_reachable_strict/#{template}", __DIR__)

      assert {:ok, result} =
               TemplateCompile.compile_watch_template(template,
                 plan_ir_mode: :primary,
                 plan_ir_strict: true,
                 out_dir: out_dir
               )

      Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(result.ir))

      on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

      decl_map = TemplateCompile.decl_map_from_result(result)

      reachable =
        PrimaryCoverage.reachable_report(decl_map, ir: result.ir, entry_module: "Main")

      assert reachable.total > 0

      assert reachable.lowered == reachable.total,
             "#{template} reachable #{reachable.lowered}/#{reachable.total}: #{inspect(Enum.take(reachable.failed, 8))}"

      fallbacks =
        (result.layout_coercion_diagnostics || [])
        |> Enum.filter(&(&1["code"] == "plan_primary_fallback"))

      assert fallbacks == []

      c_path = Path.join(out_dir, "c/elmc_generated.c")

      if File.regular?(c_path) do
        unknown_count =
          c_path
          |> File.read!()
          |> then(&Regex.scan(~r/elmc_unknown\b/, &1))
          |> length()

        assert unknown_count == 0
      end
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

    assert yes_report.total == 21
    assert yes_report.lowered == yes_report.total
  end
end
