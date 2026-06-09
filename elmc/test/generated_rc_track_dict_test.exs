defmodule Elmc.GeneratedRcTrackDictTest do
  use ExUnit.Case, async: true

  alias Elmc.Test.RcTrackCoreTest

  @module "RcTrackDictProbe"
  @project_dir Path.expand("fixtures/rc_track_dict_project", __DIR__)
  @out_dir Path.expand("tmp/rc_track_dict", __DIR__)

  @probes ~w(
    probeEmpty probeSingleton probeFromList probeInsert probeGet probeMember probeSize
    probeRemove probeIsEmpty probeKeys probeValues probeToList probeMap probeFoldl
    probeFoldr probeFilter probePartition probeUnion probeIntersect probeDiff
    probeMerge probeUpdate
  )

  @matrix ~w(
    Dict.empty Dict.singleton Dict.fromList Dict.insert Dict.get Dict.member Dict.size
    Dict.remove Dict.isEmpty Dict.keys Dict.values Dict.toList Dict.map Dict.foldl
    Dict.foldr Dict.filter Dict.partition Dict.union Dict.intersect Dict.diff
    Dict.merge Dict.update
  )

  @tag :rc_track
  @tag :rc_track_core
  test "elm/core Dict probes balance rc registry" do
    RcTrackCoreTest.run_int_suite!(
      project_dir: @project_dir,
      out_dir: @out_dir,
      module: @module,
      binary: "rc_track_dict",
      probes: @probes
    )
  end

  @tag :rc_track
  @tag :rc_track_core
  test "every codegen matrix Dict function has an rc probe" do
    RcTrackCoreTest.assert_matrix_coverage!(@probes, @matrix, "Dict")
  end
end
