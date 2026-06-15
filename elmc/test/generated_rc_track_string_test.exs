defmodule Elmc.GeneratedRcTrackStringTest do
  use ExUnit.Case, async: true

  alias Elmc.Test.RcTrackCoreTest

  @module "RcTrackStringProbe"
  @project_dir Path.expand("fixtures/rc_track_string_project", __DIR__)
  @out_dir Path.expand("tmp/rc_track_string", __DIR__)

  @probes ~w(
    probeAppend probeIsEmpty probeLength probeReverse probeRepeat probeReplace
    probeFromInt probeToInt probeFromFloat probeToFloat probeToUpper probeToLower
    probeTrim probeTrimLeft probeTrimRight probeContains probeStartsWith probeEndsWith
    probeSplit probeJoin probeWords probeLines probeSlice probeLeft probeRight
    probeDropLeft probeDropRight probeCons probeUncons probeToList probeFromList
    probeFromChar probePad probePadLeft probePadRight probeMap probeFilter probeFoldl
    probeFoldr probeAny probeAll probeIndexes
  )

  @matrix ~w(
    String.append String.isEmpty String.length String.reverse String.repeat String.replace
    String.fromInt String.toInt String.fromFloat String.toFloat String.toUpper String.toLower
    String.trim String.trimLeft String.trimRight String.contains String.startsWith String.endsWith
    String.split String.join String.words String.lines String.slice String.left String.right
    String.dropLeft String.dropRight String.cons String.uncons String.toList String.fromList
    String.fromChar String.pad String.padLeft String.padRight String.map String.filter
    String.foldl String.foldr String.any String.all String.indexes
  )

  @tag :rc_track
  @tag :rc_track_core
  test "elm/core String probes balance rc registry" do
    RcTrackCoreTest.run_int_suite!(
      project_dir: @project_dir,
      out_dir: @out_dir,
      module: @module,
      binary: "rc_track_string",
      probes: @probes
    )
  end

  @tag :rc_track
  @tag :rc_track_core
  test "every codegen matrix String function has an rc probe" do
    RcTrackCoreTest.assert_matrix_coverage!(@probes, @matrix, "String")
  end
end
