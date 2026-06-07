defmodule Ide.Emulator.WatchfaceDigitalLiveTest do
  @moduledoc """
  Live embedded-emulator smoke for the `watchface-digital` template.

  Run with:

      ELMC_RUN_EMBEDDED_EMULATOR_LIVE=1 mix test test/ide/emulator/watchface_digital_live_test.exs

  Requires Pebble QEMU images and toolchain (see `Ide.Emulator.runtime_status/1`).
  """
  use Ide.DataCase, async: false

  alias Ide.Emulator
  alias Ide.Emulator.LogCapture
  alias Ide.Emulator.Workflow
  alias Ide.Projects
  alias Ide.TestSupport.EmulatorSessionEnv

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "ide_emulator_digital_live_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:ide, Ide.Projects, projects_root: root)
    on_exit(fn -> File.rm_rf(root) end)
    :ok
  end

  @tag timeout: 300_000
  test "digital watchface installs and runs without fault on basalt" do
    run_live_platform("basalt")
  end

  defp run_live_platform(platform) do
    if run_live?() do
      EmulatorSessionEnv.run_live(fn ->
        slug = "emulator-digital-#{System.unique_integer([:positive])}"

        assert {:ok, project} =
                 Projects.create_project(%{
                   "name" => "Emulator Digital",
                   "slug" => slug,
                   "target_type" => "watchface",
                   "template" => "watchface-digital"
                 })

        on_exit(fn -> Projects.delete_project(project) end)

        assert {:ok, launched} = Workflow.launch_project(project, platform)
        session_id = launched.session.id

        try do
          assert :ok = Workflow.wait_display_ready(session_id, timeout_ms: 120_000)
          Process.sleep(3_000)

          {:ok, ctx} = Emulator.log_capture_context(session_id)

          log_task =
            Task.async(fn ->
              LogCapture.snapshot(ctx, duration_ms: 30_000)
            end)

          assert {:ok, install_result} = Emulator.install(session_id)
          assert is_binary(install_result.uuid)

          :ok = Emulator.request_app_logs(session_id)
          Process.sleep(12_000)

          snapshot = Task.await(log_task, 40_000)

          IO.puts("\n--- digital install uuid=#{install_result.uuid} ---")
          IO.puts("--- lines (#{length(snapshot.lines)}) fault_detected=#{snapshot.fault_detected} ---")
          Enum.take(snapshot.lines, 80) |> Enum.each(&IO.puts/1)
          IO.puts("--- console tail ---")
          IO.puts(String.slice(snapshot.console.output, -4000, 4000))
          IO.puts("--- end ---\n")

          refute snapshot.fault_detected,
                 "expected no App fault; lines:\n#{Enum.join(snapshot.lines, "\n")}\nconsole:\n#{snapshot.console.output}"

          assert Enum.any?(snapshot.lines, fn line ->
                   String.contains?(line, "AppRunState start") and
                     String.contains?(line, install_result.uuid)
                 end)

          refute Enum.any?(snapshot.lines, fn line ->
                   String.contains?(line, "AppRunState stop") and
                     String.contains?(line, String.downcase(install_result.uuid))
                 end),
                 "watchface should stay running after install"

          assert {:ok, pinged} = Emulator.ping(session_id)
          assert pinged.display_ready == true

          assert {:ok, png} = Emulator.screenshot(session_id, [])
          assert byte_size(png) > 500
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
