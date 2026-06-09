defmodule Elmc.GeneratedRcTrackCharTest do
  use ExUnit.Case, async: true

  alias Elmc.Test.RcTrackCoreTest

  @module "RcTrackCharProbe"
  @project_dir Path.expand("fixtures/rc_track_char_project", __DIR__)
  @out_dir Path.expand("tmp/rc_track_char", __DIR__)

  @probes ~w(
    probeToCode probeFromCode probeIsUpper probeIsLower probeIsAlpha probeIsAlphaNum
    probeIsDigit probeIsOctDigit probeIsHexDigit probeToUpper probeToLower
  )

  @matrix ~w(
    Char.toCode Char.fromCode Char.isUpper Char.isLower Char.isAlpha Char.isAlphaNum
    Char.isDigit Char.isOctDigit Char.isHexDigit Char.toUpper Char.toLower
  )

  @tag :rc_track
  @tag :rc_track_core
  test "elm/core Char probes balance rc registry" do
    RcTrackCoreTest.run_int_suite!(
      project_dir: @project_dir,
      out_dir: @out_dir,
      module: @module,
      binary: "rc_track_char",
      probes: @probes
    )
  end

  @tag :rc_track
  @tag :rc_track_core
  test "every codegen matrix Char function has an rc probe" do
    RcTrackCoreTest.assert_matrix_coverage!(@probes, @matrix, "Char")
  end
end
