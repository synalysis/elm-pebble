defmodule Elmc.GeneratedRcTrackMaybeTest do
  use ExUnit.Case, async: true

  alias Elmc.Test.RcTrackCoreTest

  @module "RcTrackMaybeProbe"
  @project_dir Path.expand("fixtures/rc_track_maybe_project", __DIR__)
  @out_dir Path.expand("tmp/rc_track_maybe", __DIR__)

  @probes ~w(probeWithDefault probeMap probeMap2 probeAndThen)

  @matrix ~w(
    Maybe.withDefault Maybe.map Maybe.map2 Maybe.andThen
  )

  @tag :rc_track
  @tag :rc_track_core
  test "elm/core Maybe probes balance rc registry" do
    RcTrackCoreTest.run_int_suite!(
      project_dir: @project_dir,
      out_dir: @out_dir,
      module: @module,
      binary: "rc_track_maybe",
      probes: @probes
    )
  end

  @tag :rc_track
  @tag :rc_track_core
  test "every codegen matrix Maybe function has an rc probe" do
    RcTrackCoreTest.assert_matrix_coverage!(@probes, @matrix, "Maybe")
  end
end
