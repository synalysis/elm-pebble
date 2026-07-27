defmodule Elmc.GeneratedRcTrackTupleTest do
  use ExUnit.Case, async: true

  alias Elmc.Test.RcTrackCoreTest
  alias Elmc.Test.RcTrackMatrix

  @module_name "Tuple"

  @tag :rc_track
  @tag :rc_track_core
  test "elm/core Tuple probes balance rc registry" do
    RcTrackCoreTest.run_core_module_suite!(@module_name, test_dir: __DIR__)
  end

  @tag :rc_track
  @tag :rc_track_core
  test "every codegen matrix Tuple function has an rc probe" do
    %{probes: probes} = RcTrackMatrix.registry_entry(@module_name)

    RcTrackCoreTest.assert_matrix_coverage!(
      probes,
      RcTrackMatrix.functions_for(@module_name),
      @module_name,
      RcTrackMatrix.matrix_probe_exceptions(@module_name)
    )
  end
end
