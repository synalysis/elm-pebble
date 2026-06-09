defmodule Elmc.GeneratedRcTrackTupleTest do
  use ExUnit.Case, async: true

  alias Elmc.Test.RcTrackCoreTest

  @module "RcTrackTupleProbe"
  @project_dir Path.expand("fixtures/rc_track_tuple_project", __DIR__)
  @out_dir Path.expand("tmp/rc_track_tuple", __DIR__)

  @probes ~w(probeFirst probeSecond probePair probeMapFirst probeMapSecond probeMapBoth)

  @matrix ~w(
    Tuple.pair Tuple.first Tuple.second Tuple.mapFirst Tuple.mapSecond Tuple.mapBoth
  )

  @tag :rc_track
  @tag :rc_track_core
  test "elm/core Tuple probes balance rc registry" do
    RcTrackCoreTest.run_int_suite!(
      project_dir: @project_dir,
      out_dir: @out_dir,
      module: @module,
      binary: "rc_track_tuple",
      probes: @probes
    )
  end

  @tag :rc_track
  @tag :rc_track_core
  test "every codegen matrix Tuple function has an rc probe" do
    RcTrackCoreTest.assert_matrix_coverage!(@probes, @matrix, "Tuple", %{"Pair" => "Tuple.pair"})
  end
end
