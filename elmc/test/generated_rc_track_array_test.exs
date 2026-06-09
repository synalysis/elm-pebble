defmodule Elmc.GeneratedRcTrackArrayTest do
  use ExUnit.Case, async: true

  alias Elmc.Test.RcTrackCoreTest

  @module "RcTrackArrayProbe"
  @project_dir Path.expand("fixtures/rc_track_array_project", __DIR__)
  @out_dir Path.expand("tmp/rc_track_array", __DIR__)

  @probes ~w(
    probeEmpty probeFromList probeLength probeGet probeSet probePush probeInitialize
    probeRepeat probeIsEmpty probeToList probeToIndexedList probeMap probeIndexedMap
    probeFoldl probeFoldr probeFilter probeAppend probeSlice
  )

  @matrix ~w(
    Array.empty Array.fromList Array.length Array.get Array.set Array.push Array.initialize
    Array.repeat Array.isEmpty Array.toList Array.toIndexedList Array.map Array.indexedMap
    Array.foldl Array.foldr Array.filter Array.append Array.slice
  )

  @tag :rc_track
  @tag :rc_track_core
  test "elm/core Array probes balance rc registry" do
    RcTrackCoreTest.run_int_suite!(
      project_dir: @project_dir,
      out_dir: @out_dir,
      module: @module,
      binary: "rc_track_array",
      probes: @probes
    )
  end

  @tag :rc_track
  @tag :rc_track_core
  test "every codegen matrix Array function has an rc probe" do
    RcTrackCoreTest.assert_matrix_coverage!(@probes, @matrix, "Array")
  end
end
