defmodule Elmc.GeneratedRcTrackMatrixTest do
  @moduledoc """
  Single RC_TRACK matrix: every elm/core registry module runs its probe suite.
  Prefer this over per-module `generated_rc_track_*_test.exs` wrappers.
  """

  use ExUnit.Case, async: true

  alias Elmc.Test.RcTrackCoreTest
  alias Elmc.Test.RcTrackMatrix

  @tag :rc_track
  @tag :rc_track_gate
  test "CODEGEN_COVERAGE_MATRIX elm/core functions align with core.ex special_value targets" do
    RcTrackMatrix.assert_core_ex_alignment!()
  end

  @tag :rc_track
  @tag :rc_track_gate
  test "every elm/core matrix module has a registered rc probe suite" do
    matrix_modules = RcTrackMatrix.core_module_names()

    registry_modules =
      RcTrackMatrix.registry()
      |> Map.keys()
      |> Enum.sort()

    missing_registry = matrix_modules -- registry_modules
    assert missing_registry == [], "missing rc probe registry for: #{inspect(missing_registry)}"
  end

  for {module_name, _entry} <- RcTrackMatrix.registry() do
    @tag :rc_track
    @tag :rc_track_core
    @tag :rc_track_gate
    test "elm/core #{module_name} probes balance rc registry and cover the matrix" do
      module_name = unquote(module_name)
      RcTrackCoreTest.run_core_module_suite!(module_name, test_dir: __DIR__)

      %{probes: probes} = RcTrackMatrix.registry_entry(module_name)
      prefix = if module_name == "Task", do: "Task", else: module_name

      RcTrackCoreTest.assert_matrix_coverage!(
        probes,
        RcTrackMatrix.functions_for(module_name),
        prefix,
        RcTrackMatrix.matrix_probe_exceptions(module_name)
      )
    end
  end
end
