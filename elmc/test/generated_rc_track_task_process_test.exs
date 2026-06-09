defmodule Elmc.GeneratedRcTrackTaskProcessTest do
  use ExUnit.Case, async: true

  alias Elmc.Test.RcTrackCoreTest

  @module "RcTrackTaskProcessProbe"
  @project_dir Path.expand("fixtures/rc_track_task_process_project", __DIR__)
  @out_dir Path.expand("tmp/rc_track_task_process", __DIR__)

  @probes ~w(probeSucceed probeFail probeSpawn probeSleep probeKill)

  @matrix ~w(
    Task.succeed Task.fail Process.spawn Process.sleep Process.kill
  )

  @tag :rc_track
  @tag :rc_track_core
  test "elm/core Task and Process probes balance rc registry" do
    RcTrackCoreTest.run_int_suite!(
      project_dir: @project_dir,
      out_dir: @out_dir,
      module: @module,
      binary: "rc_track_task_process",
      probes: @probes
    )
  end

  @tag :rc_track
  @tag :rc_track_core
  test "every codegen matrix Task/Process function has an rc probe" do
    RcTrackCoreTest.assert_matrix_coverage!(
      @probes,
      @matrix,
      "Task",
      %{
        "Spawn" => "Process.spawn",
        "Sleep" => "Process.sleep",
        "Kill" => "Process.kill"
      }
    )
  end
end
