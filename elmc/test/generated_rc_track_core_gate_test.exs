defmodule Elmc.GeneratedRcTrackCoreGateTest do
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
    @tag :rc_track
    @tag :rc_track_gate
    test "every codegen matrix #{module_name} function has an rc probe" do
      module_name = unquote(module_name)
      %{probes: probes} = RcTrackMatrix.registry_entry(module_name)
      matrix = RcTrackMatrix.functions_for(module_name)
      prefix = if module_name == "Task", do: "Task", else: module_name

      RcTrackCoreTest.assert_matrix_coverage!(
        probes,
        matrix,
        prefix,
        RcTrackMatrix.matrix_probe_exceptions(module_name)
      )
    end
  end

  @tag :rc_track
  @tag :rc_track_gate
  test "every registered rc probe fixture directory exists" do
    for {_module, %{fixture: fixture}} <- RcTrackMatrix.registry() do
      path = Path.expand(fixture, __DIR__)
      assert File.dir?(path), "missing rc track fixture: #{fixture}"
    end
  end
end
