Mix.Task.run("app.start")

alias Ide.{Emulator, Emulator.LogCapture, ProjectTemplates, PebbleToolchain}

fixture = Path.join(__DIR__, "fixtures/elmtris_minimal_main.elm")
workspace = Path.join(System.tmp_dir!(), "min_#{System.unique_integer([:positive])}")
:ok = ProjectTemplates.apply_template("game-elmtris", workspace)
File.cp!(fixture, Path.join(workspace, "watch/src/Main.elm"))

{:ok, pkg} =
  PebbleToolchain.package("p",
    workspace_root: workspace,
    target_type: "app",
    project_name: "P",
    target_platforms: ["diorite"],
    source_roots: ["watch", "protocol", "phone"],
    emulator_storage_logs: true
  )

{:ok, session} =
  Emulator.launch(project_slug: "p", platform: "diorite", artifact_path: pkg.artifact_path)

:ok =
  Stream.repeatedly(fn ->
    case Emulator.ping(session.id) do
      {:ok, %{display_ready: true}} -> :ok
      _ -> :wait
    end
  end)
  |> Enum.find_value(fn
    :ok -> :ok
    :wait -> Process.sleep(250)
    nil
  end)

{:ok, ctx} = Emulator.log_capture_context(session.id)
log_task = Task.async(fn -> LogCapture.snapshot(ctx, duration_ms: 20_000) end)
{:ok, install} = Emulator.install(session.id)
Process.sleep(12_000)
snap = Task.await(log_task, 30_000)

stopped? =
  Enum.any?(snap.lines, fn line ->
    String.contains?(line, "AppRunState stop") and
      String.contains?(line, String.downcase(install.uuid))
  end)

IO.puts(
  "pbw=#{File.stat!(pkg.artifact_path).size} stopped=#{stopped?} has_log=#{snap.output =~ "AppLog"}"
)

if snap.output =~ "AppLog", do: IO.puts(snap.output)
Emulator.kill(session.id)
System.halt(if stopped?, do: 2, else: 0)
