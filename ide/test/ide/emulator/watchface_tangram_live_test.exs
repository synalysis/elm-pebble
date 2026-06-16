defmodule Ide.Emulator.WatchfaceTangramLiveTest do
  @moduledoc """
  Live embedded-emulator smoke for the `watchface-tangram-time` template.

  Run with:

      ELMC_RUN_EMBEDDED_EMULATOR_LIVE=1 mix test test/ide/emulator/watchface_tangram_live_test.exs

  Requires Pebble QEMU images and toolchain (see `Ide.Emulator.runtime_status/1`).
  """
  use Ide.DataCase, async: false

  @moduletag :live_emulator

  alias Ide.Emulator
  alias Ide.Emulator.LogCapture
  alias Ide.Emulator.Workflow
  alias Ide.Projects
  alias Ide.TestSupport.EmulatorSessionEnv

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "ide_emulator_tangram_live_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:ide, Ide.Projects, projects_root: root)
    on_exit(fn -> File.rm_rf(root) end)
    :ok
  end

  @tag timeout: 300_000
  test "tangram watchface installs and stays running on basalt (IDE-like flow)" do
    if run_live?() do
      EmulatorSessionEnv.run_live(fn ->
        slug = "emulator-tangram-#{System.unique_integer([:positive])}"

        assert {:ok, project} =
                 Projects.create_project(%{
                   "name" => "Emulator Tangram",
                   "slug" => slug,
                   "target_type" => "watchface",
                   "template" => "watchface-tangram-time"
                 })

        on_exit(fn -> Projects.delete_project(project) end)

        assert {:ok, launched} = Workflow.launch_project(project, "basalt")
        session_id = launched.session.id

        try do
          assert :ok = Workflow.wait_display_ready(session_id, timeout_ms: 120_000)
          Process.sleep(2_000)

          assert {:ok, install_result} = Emulator.install(session_id)
          assert is_binary(install_result.uuid)

          Process.sleep(8_000)
          :ok = Emulator.request_app_logs(session_id)
          Process.sleep(10_000)

          {:ok, ctx} = Emulator.log_capture_context(session_id)
          snapshot = LogCapture.snapshot(ctx, duration_ms: 15_000)

          uuid_down = String.downcase(install_result.uuid)

          refute snapshot.fault_detected,
                 "expected no App fault; lines:\n#{Enum.join(snapshot.lines, "\n")}"

          refute Enum.any?(snapshot.lines, fn line ->
                   String.contains?(line, "AppRunState stop") and
                     String.contains?(line, uuid_down)
                 end),
                 "tangram watchface should stay running after install and companion startup"

          assert {:ok, pinged} = Emulator.ping(session_id)
          assert pinged.display_ready == true

          assert {:ok, png} = Emulator.screenshot(session_id, [])
          assert byte_size(png) > 400
        after
          _ = Emulator.kill(session_id)
        end
      end)
    else
      assert true
    end
  end

  defp run_live? do
    System.get_env("ELMC_RUN_EMBEDDED_EMULATOR_LIVE", "0") in ["1", "true", "TRUE", "yes", "YES"]
  end
end
