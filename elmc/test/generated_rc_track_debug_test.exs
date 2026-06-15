defmodule Elmc.GeneratedRcTrackDebugTest do
  use ExUnit.Case, async: true

  alias Elmc.Test.RcTrackCoreTest

  @module "RcTrackDebugProbe"
  @project_dir Path.expand("fixtures/rc_track_debug_project", __DIR__)
  @out_dir Path.expand("tmp/rc_track_debug", __DIR__)

  @probes ~w(probeLog probeTodo probeToString)

  @matrix ~w(Debug.log Debug.todo Debug.toString)

  @tag :rc_track
  @tag :rc_track_core
  test "elm/core Debug probes balance rc registry" do
    RcTrackCoreTest.run_int_suite!(
      project_dir: @project_dir,
      out_dir: @out_dir,
      module: @module,
      binary: "rc_track_debug",
      probes: @probes
    )
  end

  @tag :rc_track
  @tag :rc_track_core
  test "every codegen matrix Debug function has an rc probe" do
    RcTrackCoreTest.assert_matrix_coverage!(@probes, @matrix, "Debug")
  end
end
