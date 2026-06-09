defmodule Elmc.GeneratedRcTrackBitwiseTest do
  use ExUnit.Case, async: true

  alias Elmc.Test.RcTrackCoreTest

  @module "RcTrackBitwiseProbe"
  @project_dir Path.expand("fixtures/rc_track_bitwise_project", __DIR__)
  @out_dir Path.expand("tmp/rc_track_bitwise", __DIR__)

  @probes ~w(
    probeAnd probeOr probeXor probeComplement probeShiftLeftBy probeShiftRightBy
    probeShiftRightZfBy
  )

  @matrix ~w(
    Bitwise.and Bitwise.or Bitwise.xor Bitwise.complement Bitwise.shiftLeftBy
    Bitwise.shiftRightBy Bitwise.shiftRightZfBy
  )

  @tag :rc_track
  @tag :rc_track_core
  test "elm/core Bitwise probes balance rc registry" do
    RcTrackCoreTest.run_int_suite!(
      project_dir: @project_dir,
      out_dir: @out_dir,
      module: @module,
      binary: "rc_track_bitwise",
      probes: @probes
    )
  end

  @tag :rc_track
  @tag :rc_track_core
  test "every codegen matrix Bitwise function has an rc probe" do
    RcTrackCoreTest.assert_matrix_coverage!(@probes, @matrix, "Bitwise")
  end
end
