defmodule Elmc.GeneratedRcTrackSetTest do
  use ExUnit.Case, async: true

  alias Elmc.Test.RcTrackCoreTest

  @module "RcTrackSetProbe"
  @project_dir Path.expand("fixtures/rc_track_set_project", __DIR__)
  @out_dir Path.expand("tmp/rc_track_set", __DIR__)

  @probes ~w(
    probeEmpty probeSingleton probeFromList probeInsert probeMember probeSize
    probeRemove probeIsEmpty probeToList probeUnion probeIntersect probeDiff
    probeMap probeFoldl probeFoldr probeFilter probePartition
  )

  @matrix ~w(
    Set.empty Set.singleton Set.fromList Set.insert Set.member Set.size Set.remove
    Set.isEmpty Set.toList Set.union Set.intersect Set.diff Set.map Set.foldl
    Set.foldr Set.filter Set.partition
  )

  @tag :rc_track
  @tag :rc_track_core
  test "elm/core Set probes balance rc registry" do
    RcTrackCoreTest.run_int_suite!(
      project_dir: @project_dir,
      out_dir: @out_dir,
      module: @module,
      binary: "rc_track_set",
      probes: @probes
    )
  end

  @tag :rc_track
  @tag :rc_track_core
  test "every codegen matrix Set function has an rc probe" do
    RcTrackCoreTest.assert_matrix_coverage!(@probes, @matrix, "Set")
  end
end
