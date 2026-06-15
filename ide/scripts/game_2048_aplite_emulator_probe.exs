# Usage: cd ide && mix run scripts/game_2048_aplite_emulator_probe.exs

Mix.Task.run("app.start")

alias Ide.Emulator
alias Ide.Emulator.LogCapture
alias Ide.PebbleToolchain

unless Emulator.runtime_status("aplite").missing == [] do
  IO.puts("embedded emulator not ready: #{inspect(Emulator.runtime_status("aplite").missing)}")
  System.halt(1)
end

workspace = "/home/ape/projects/elm-pebble/ide/workspace_projects/2048"

{:ok, pkg} =
  PebbleToolchain.package("2048",
    workspace_root: workspace,
    target_type: "app",
    project_name: "2048",
    target_platforms: ["aplite"],
    source_roots: ["watch", "protocol", "phone"]
  )

{:ok, session} =
  Emulator.launch(
    project_slug: "2048",
    platform: "aplite",
    artifact_path: pkg.artifact_path
  )

session_id = session.id

try do
  deadline = System.monotonic_time(:millisecond) + 120_000

  :ok =
    Stream.repeatedly(fn ->
      case Emulator.ping(session_id) do
        {:ok, %{display_ready: true}} -> :ok
        _ -> :wait
      end
    end)
    |> Enum.find_value(fn
      :ok -> :ok
      :wait ->
        if System.monotonic_time(:millisecond) >= deadline do
          :timeout
        else
          Process.sleep(250)
          nil
        end
    end)
    |> case do
      :ok -> :ok
      _ -> System.halt(3)
    end

  {:ok, ctx} = Emulator.log_capture_context(session_id)

  log_task =
    Task.async(fn ->
      LogCapture.snapshot(ctx, duration_ms: 25_000)
    end)

  {:ok, install} = Emulator.install(session_id)
  :ok = Emulator.request_app_logs(session_id)
  Process.sleep(15_000)

  snap = Task.await(log_task, 35_000)

  stopped? =
    Enum.any?(snap.lines, fn line ->
      String.contains?(line, "AppRunState stop") and
        String.contains?(line, String.downcase(install.uuid))
    end)

  IO.puts("game-2048 aplite fault=#{snap.fault_detected} stopped=#{stopped?}")
  System.halt(if snap.fault_detected or stopped?, do: 2, else: 0)
after
  Emulator.kill(session_id)
end
