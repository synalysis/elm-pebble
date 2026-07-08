defmodule Elmc.PlanTemplatesPrimaryAuditTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Plan.PrimaryCoverage
  alias Elmc.TestSupport.TemplateCompile

  @moduletag :plan_surface
  @moduletag :slow

  defp audit_template(template, expected_counts \\ nil) do
    assert {:ok, result} =
             TemplateCompile.compile_watch_template(template, plan_ir_mode: :primary)

    Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(result.ir))

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl_map = TemplateCompile.decl_map_from_result(result)
    report = PrimaryCoverage.main_functions_report(decl_map, ir: result.ir)

    reachable_report =
      PrimaryCoverage.reachable_report(decl_map, ir: result.ir, entry_module: "Main")

    fallbacks =
      (result.layout_coercion_diagnostics || [])
      |> Enum.filter(&(&1["code"] == "plan_primary_fallback"))
      |> Enum.filter(fn diag ->
        case Regex.run(~r/Function ([^.]+)\./, diag["message"] || "") do
          [_, mod] -> mod == "Main"
          _ -> true
        end
      end)

    case expected_counts do
      {total, lowered} ->
        assert report.total == total
        assert report.lowered == lowered

      _ ->
        :ok
    end

    assert fallbacks == [],
           "#{template} plan_primary_fallback: #{inspect(Enum.map(fallbacks, & &1["message"]))}"

    assert reachable_report.lowered == reachable_report.total,
           "#{template} reachable plan coverage #{reachable_report.lowered}/#{reachable_report.total}: #{inspect(Enum.take(reachable_report.failed, 8))}"

    {report, reachable_report}
  end

  test "game_elmtris primary has full Main coverage and no fallbacks" do
    {report, _} = audit_template("game_elmtris", {44, 44})
    assert report.lowered == report.total
  end

  test "watchface_yes primary has full Main and reachable coverage" do
    {report, _} = audit_template("watchface_yes", {55, 55})
    assert report.lowered == report.total
  end

  test "game_2048 primary has no plan_primary_fallback warnings" do
    audit_template("game_2048")
  end

  test "watchface_analog primary has no plan_primary_fallback warnings" do
    audit_template("watchface_analog")
  end

  test "watchface_digital primary has no plan_primary_fallback warnings" do
    audit_template("watchface_digital")
  end

  test "app_minimal primary has no plan_primary_fallback warnings" do
    audit_template("app_minimal")
  end

  test "game_tiny_bird primary has no plan_primary_fallback warnings" do
    audit_template("game_tiny_bird")
  end
end
