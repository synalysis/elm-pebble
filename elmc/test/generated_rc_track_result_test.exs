defmodule Elmc.GeneratedRcTrackResultTest do
  use ExUnit.Case, async: true

  alias Elmc.Test.RcTrackCoreTest

  @module "RcTrackResultProbe"
  @project_dir Path.expand("fixtures/rc_track_result_project", __DIR__)
  @out_dir Path.expand("tmp/rc_track_result", __DIR__)

  @probes ~w(
    probeMap probeMapError probeAndThen probeWithDefault probeToMaybe probeFromMaybe
  )

  @matrix ~w(
    Result.map Result.mapError Result.andThen Result.withDefault Result.toMaybe Result.fromMaybe
  )

  @tag :rc_track
  @tag :rc_track_core
  test "elm/core Result probes balance rc registry" do
    RcTrackCoreTest.run_int_suite!(
      project_dir: @project_dir,
      out_dir: @out_dir,
      module: @module,
      binary: "rc_track_result",
      probes: @probes
    )
  end

  @tag :rc_track
  @tag :rc_track_core
  test "every codegen matrix Result function has an rc probe" do
    RcTrackCoreTest.assert_matrix_coverage!(@probes, @matrix, "Result")
  end
end
