defmodule Elmc.PlanStrictPolicyTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.StrictPolicy
  alias Elmc.CLI

  test "strict defaults on for primary mode" do
    assert StrictPolicy.strict?(%{plan_ir_mode: :primary})
    assert StrictPolicy.strict?(plan_ir_mode: :primary)
    refute StrictPolicy.strict?(%{plan_ir_mode: :primary, plan_ir_strict: false})
    refute StrictPolicy.strict?(%{plan_ir_mode: :shadow})
    refute StrictPolicy.strict?(%{plan_ir_mode: :off})
  end

  test "gap and reachable fallback severities follow strict policy" do
    assert StrictPolicy.gap_severity(%{plan_ir_mode: :primary}) == "error"
    assert StrictPolicy.gap_severity(%{plan_ir_mode: :primary, plan_ir_strict: false}) == "warning"
    assert StrictPolicy.gap_severity(%{plan_ir_mode: :shadow}) == "info"

    assert StrictPolicy.fallback_severity(%{plan_ir_mode: :primary}, true) == "error"
    assert StrictPolicy.fallback_severity(%{plan_ir_mode: :primary, plan_ir_strict: false}, true) ==
             "warning"

    assert StrictPolicy.fallback_severity(%{plan_ir_mode: :primary}, false) == "warning"
  end

  test "validate_compile_result fails on strict plan_primary_gap" do
    layout = [
      %{
        "source" => "elmc/plan",
        "code" => "plan_primary_gap",
        "severity" => "error",
        "message" => "Plan IR could not lower 1 reachable function(s): Main.broken (unsupported)"
      }
    ]

    result = %{
      project: %{diagnostics: []},
      ir: %{diagnostics: []},
      debug_usage_diagnostics: [],
      layout_coercion_diagnostics: layout,
      blocking_diagnostics: layout
    }

    assert {:error, [_ | _]} = CLI.validate_compile_result(result)
  end

  test "validate_compile_result passes when only informational plan diagnostics are present" do
    result = %{
      project: %{diagnostics: []},
      ir: %{diagnostics: []},
      debug_usage_diagnostics: [],
      layout_coercion_diagnostics: [
        %{
          "source" => "elmc/plan",
          "code" => "plan_primary_coverage",
          "severity" => "info",
          "message" => "Plan IR coverage ok"
        }
      ],
      blocking_diagnostics: [],
      informational_diagnostics: [
        %{
          "source" => "elmc/plan",
          "code" => "plan_primary_coverage",
          "severity" => "info",
          "message" => "Plan IR coverage ok"
        }
      ]
    }

    assert :ok = CLI.validate_compile_result(result)
  end
end
