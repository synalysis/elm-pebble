defmodule Elmc.GeneratedRcTrackBasicsTest do
  use ExUnit.Case, async: true

  alias Elmc.Test.RcTrackCoreTest

  @module "RcTrackBasicsProbe"
  @project_dir Path.expand("fixtures/rc_track_basics_project", __DIR__)
  @out_dir Path.expand("tmp/rc_track_basics", __DIR__)

  @probes ~w(
    probeMax probeMin probeClamp probeModBy probeIdentity probeAlways probeNot
    probeNegate probeAbs probeToFloat probeRound probeFloor probeCeiling probeTruncate
    probeRemainderBy probeXor probeCompare
  )

  @matrix ~w(
    Basics.max Basics.min Basics.clamp Basics.modBy Basics.identity Basics.always
    Basics.not Basics.negate Basics.abs Basics.toFloat Basics.round Basics.floor
    Basics.ceiling Basics.truncate Basics.remainderBy Basics.xor Basics.compare
  )

  @tag :rc_track
  @tag :rc_track_core
  test "elm/core Basics probes balance rc registry" do
    RcTrackCoreTest.run_int_suite!(
      project_dir: @project_dir,
      out_dir: @out_dir,
      module: @module,
      binary: "rc_track_basics",
      probes: @probes
    )
  end

  @tag :rc_track
  @tag :rc_track_core
  test "every codegen matrix Basics function has an rc probe" do
    RcTrackCoreTest.assert_matrix_coverage!(@probes, @matrix, "Basics")
  end
end
