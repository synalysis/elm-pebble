defmodule Ide.Emulator.WatchfaceSmokeScreenLiveTest do
  @moduledoc """
  Live embedded-emulator smoke for the checkerboard `watchface-smoke-screen` template.

  Run with:

      ELMC_RUN_EMBEDDED_EMULATOR_LIVE=1 mix test test/ide/emulator/watchface_smoke_screen_live_test.exs

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

  @platforms ~w(basalt diorite)

  for platform <- @platforms do
    @tag timeout: 300_000
    test "smoke-screen watchface installs and renders checkerboard on #{platform}" do
      run_live_platform(unquote(platform))
    end
  end

  defp run_live_platform(platform) do
    if run_live?() do
      EmulatorSessionEnv.run_live(fn ->
        slug = "emulator-smoke-screen-#{System.unique_integer([:positive])}"

        assert {:ok, project} =
                 Projects.create_project(%{
                   "name" => "Emulator Smoke Screen",
                   "slug" => slug,
                   "target_type" => "watchface",
                   "template" => "watchface-smoke-screen"
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
              LogCapture.snapshot(ctx, duration_ms: 25_000)
            end)

          assert {:ok, install_result} = Emulator.install(session_id)
          assert is_binary(install_result.uuid)
          assert install_result.variant in ["basalt", "diorite", "chalk", "emery", "flint", "gabbro"]

          :ok = Emulator.request_app_logs(session_id)
          Process.sleep(10_000)

          snapshot = Task.await(log_task, 35_000)

          IO.puts("\n--- smoke-screen install uuid=#{install_result.uuid} ---")
          IO.puts("--- lines (#{length(snapshot.lines)}) fault_detected=#{snapshot.fault_detected} ---")
          Enum.take(snapshot.lines, 50) |> Enum.each(&IO.puts/1)
          IO.puts("--- end ---\n")

          refute snapshot.fault_detected,
                 "expected no App fault; lines:\n#{Enum.join(snapshot.lines, "\n")}"

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

          Process.sleep(2_000)

          assert {:ok, png} = Emulator.screenshot(session_id, [])
          assert byte_size(png) > 500

          assert {:ok, analysis} = analyze_checkerboard_png(png)

          assert analysis.pass?,
                 "expected four-quadrant checkerboard on #{platform}; #{analysis.summary}"
        after
          _ = Emulator.kill(session_id)
        end
      end)
    else
      assert true
    end
  end

  defp analyze_checkerboard_png(png) when is_binary(png) do
    path = Path.join(System.tmp_dir!(), "smoke-checkerboard-#{System.unique_integer([:positive])}.png")

    try do
      File.write!(path, png)

      script = """
      from PIL import Image
      import sys
      im = Image.open(sys.argv[1]).convert("RGB")
      w, h = im.size
      quads = [
          (0.25, 0.25, "dark"),
          (0.75, 0.25, "light"),
          (0.25, 0.75, "light"),
          (0.75, 0.75, "dark"),
      ]
      lines = []
      ok = True
      for qx, qy, expect in quads:
          x = min(int(w * qx), w - 1)
          y = min(int(h * qy), h - 1)
          r, g, b = im.getpixel((x, y))
          lum = (r * 30 + g * 59 + b * 11) // 100
          got = "dark" if lum < 128 else "light"
          if got != expect:
              ok = False
          lines.append(f"({qx},{qy})@{x},{y} rgb={r},{g},{b} expect={expect} got={got}")
      print("PASS" if ok else "FAIL")
      print("; ".join(lines))
      """

      case System.cmd("python3", ["-c", script, path], stderr_to_stdout: true) do
        {output, 0} ->
          [verdict | details] = String.split(String.trim(output), "\n", parts: 2)
          {:ok, %{pass?: verdict == "PASS", summary: List.first(details, "")}}

        {output, _} ->
          {:ok, %{pass?: false, summary: "python analysis failed: #{String.trim(output)}"}}
      end
    after
      File.rm(path)
    end
  end

  defp run_live? do
    System.get_env("ELMC_RUN_EMBEDDED_EMULATOR_LIVE", "0") in ["1", "true", "TRUE", "yes", "YES"]
  end
end
