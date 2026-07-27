defmodule Elmc.PlanRcTrackProbeExecutionTest do
  @moduledoc """
  Plan-primary RC probe execution: compile elm/core fixtures with
  `plan_ir_mode: :primary` + `plan_ir_strict: true`, then run host RC
  balance harnesses (same as `generated_rc_track_*`, but on plan-emitted C).
  """

  use ExUnit.Case, async: false

  alias Elmc.Test.RcTrackCoreTest
  alias Elmc.Test.RcTrackMatrix

  @moduletag :plan_surface
  @moduletag :slow
  @moduletag :plan_rc_track

  @plan_compile_opts [
    plan_ir_mode: :primary,
    plan_ir_strict: true,
    strip_dead_code: false
  ]

  for module_name <- [
        "Basics",
        "Bitwise",
        "List",
        "Maybe",
        "Result",
        "String",
        "Char",
        "Tuple",
        "Dict",
        "Set",
        "Array",
        "Debug",
        "Task"
      ] do
  @tag core_module: module_name
  @tag :plan_rc_track_exec

  test "plan-primary rc probes balance #{module_name}", %{core_module: module_name} do
      RcTrackCoreTest.run_core_module_suite!(module_name,
        test_dir: __DIR__,
        out_dir: Path.expand("tmp/plan_rc_track_exec/#{module_name}", __DIR__),
        binary: "plan_rc_track_#{String.downcase(module_name)}",
        compile_opts: @plan_compile_opts,
        assert_no_elmc_unknown: true
      )
    end
  end

  @tag :rc_track_gate
  test "plan-primary Basics matrix still has probe coverage" do
    %{probes: probes} = RcTrackMatrix.registry_entry("Basics")

    RcTrackCoreTest.assert_matrix_coverage!(
      probes,
      RcTrackMatrix.functions_for("Basics"),
      "Basics",
      RcTrackMatrix.matrix_probe_exceptions("Basics")
    )
  end

  @tag :rc_track_gate
  test "plan-primary List matrix still has probe coverage" do
    %{probes: probes} = RcTrackMatrix.registry_entry("List")

    RcTrackCoreTest.assert_matrix_coverage!(
      probes,
      RcTrackMatrix.functions_for("List"),
      "List",
      RcTrackMatrix.matrix_probe_exceptions("List")
    )
  end
end
