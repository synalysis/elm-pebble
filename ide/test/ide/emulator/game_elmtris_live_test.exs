defmodule Ide.Emulator.GameElmtrisLiveTest do
  @moduledoc false
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
        "ide_emulator_elmtris_live_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:ide, Ide.Projects, projects_root: root)
    on_exit(fn -> File.rm_rf(root) end)
    :ok
  end

  @tag timeout: 300_000
  test "game-elmtris stays running on diorite after install" do
    if run_live?() do
      EmulatorSessionEnv.run_live(fn ->
        slug = "emulator-elmtris-#{System.unique_integer([:positive])}"

        assert {:ok, project} =
                 Projects.create_project(%{
                   "name" => "Emulator Elmtris",
                   "slug" => slug,
                   "target_type" => "app",
                   "template" => "game-elmtris"
                 })

        on_exit(fn -> Projects.delete_project(project) end)

        assert {:ok, launched} = Workflow.launch_project(project, "diorite")
        session_id = launched.session.id

        try do
          assert :ok = Workflow.wait_display_ready(session_id, timeout_ms: 120_000)
          Process.sleep(2_000)

          {:ok, ctx} = Emulator.log_capture_context(session_id)

          log_task =
            Task.async(fn ->
              LogCapture.snapshot(ctx, duration_ms: 30_000)
            end)

          assert {:ok, install_result} = Emulator.install(session_id)
          assert is_binary(install_result.uuid)

          :ok = Emulator.request_app_logs(session_id)
          Process.sleep(15_000)

          snapshot = Task.await(log_task, 40_000)

          IO.puts("\n--- elmtris install uuid=#{install_result.uuid} ---")
          IO.puts("--- fault=#{snapshot.fault_detected} ---")
          IO.puts(snapshot.output)
          IO.puts("--- end ---\n")

          refute snapshot.fault_detected,
                 "expected no App fault; output:\n#{snapshot.output}"

          refute Enum.any?(snapshot.lines, fn line ->
                   String.contains?(line, "AppRunState stop") and
                     String.contains?(line, String.downcase(install_result.uuid))
                 end),
                 "app should not stop immediately after install"

          assert {:ok, pinged} = Emulator.ping(session_id)
          assert pinged.display_ready == true
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
