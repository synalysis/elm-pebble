defmodule Elmc.PlanCoverageDiagnosticsTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Plan.PrimaryCoverage

  test "primary emits info diagnostic when reachable coverage is complete" do
    summary = %{
      available: true,
      pruned_count: 89,
      plan_coverage: %{
        "main" => %{"lowered" => 55, "total" => 55, "failed_count" => 0},
        "reachable" => %{"lowered" => 79, "total" => 79, "failed_count" => 0}
      }
    }

    [diag] = PrimaryCoverage.compile_diagnostics(summary, plan_ir_mode: :primary)

    assert diag["code"] == "plan_primary_coverage"
    assert diag["severity"] == "info"
    assert diag["message"] =~ "79/79 reachable"
    assert diag["message"] =~ "89 dead helpers pruned"
    assert diag["message"] =~ "Main 55/55"
    assert diag["message"] =~ "primary strict"
  end

  test "primary warns when reachable functions fail to lower and strict is off" do
    summary = %{
      available: true,
      plan_coverage: %{
        "reachable" => %{
          "lowered" => 2,
          "total" => 3,
          "failed_count" => 1,
          "failed_preview" => [%{"module" => "Main", "name" => "broken", "reason" => "unsupported"}]
        }
      }
    }

    [diag] = PrimaryCoverage.compile_diagnostics(summary, plan_ir_mode: :primary, plan_ir_strict: false)

    assert diag["code"] == "plan_primary_gap"
    assert diag["severity"] == "warning"
    assert diag["message"] =~ "Main.broken"
  end

  test "primary errors when reachable functions fail to lower under strict policy" do
    summary = %{
      available: true,
      plan_coverage: %{
        "reachable" => %{
          "lowered" => 2,
          "total" => 3,
          "failed_count" => 1,
          "failed_preview" => [%{"module" => "Main", "name" => "broken", "reason" => "unsupported"}]
        }
      }
    }

    [diag] = PrimaryCoverage.compile_diagnostics(summary, plan_ir_mode: :primary)

    assert diag["code"] == "plan_primary_gap"
    assert diag["severity"] == "error"
  end

  test "compile attaches plan coverage diagnostic for game_elmtris primary" do
    out_dir = Path.expand("tmp/plan_coverage_diag_elmtris", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, result} =
             Elmc.TestSupport.TemplateCompile.compile_watch_template("game_elmtris",
               plan_ir_mode: :primary,
               out_dir: out_dir
             )

    assert is_map(result.plan_coverage)
    assert get_in(result.plan_coverage, ["reachable", "failed_count"]) == 0

    assert Enum.any?(result.layout_coercion_diagnostics, fn diag ->
             diag["code"] == "plan_primary_coverage"
           end)

    refute Enum.any?(result.layout_coercion_diagnostics, &(&1["code"] == "plan_primary_gap"))
    refute Enum.any?(result.layout_coercion_diagnostics, &(&1["code"] == "plan_primary_fallback"))

    assert result.plan_toolchain == %{mode: :primary, strict: true}
  end

  test "explicit plan_ir_mode off emits legacy codegen info diagnostic" do
    out_dir = Path.expand("tmp/plan_legacy_diag", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, result} =
             Elmc.compile(Path.expand("fixtures/simple_project", __DIR__), %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :off
             })

    assert Enum.any?(result.layout_coercion_diagnostics, fn diag ->
             diag["code"] == "plan_legacy_codegen" and diag["severity"] == "info"
           end)
  end
end
