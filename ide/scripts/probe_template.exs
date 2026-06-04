Mix.Task.run("app.start")

[template, platform] = System.argv() |> case do
  [t, p] -> {t, p}
  [t] -> {t, "diorite"}
  _ -> {"game-2048", "diorite"}
end

alias Ide.{Emulator, Emulator.LogCapture, ProjectTemplates, PebbleToolchain}

unless Emulator.runtime_status(platform).missing == [] do
  IO.puts("emulator not ready: #{inspect(Emulator.runtime_status(platform).missing)}")
  System.halt(1)
end

workspace = Path.join(System.tmp_dir!(), "probe_#{template}_#{System.unique_integer([:positive])}")
File.mkdir_p!(workspace)
:ok = ProjectTemplates.apply_template(template, workspace)

{:ok, pkg} =
  PebbleToolchain.package("probe",
    workspace_root: workspace,
    target_type: "app",
    project_name: "Probe",
    target_platforms: [platform],
    source_roots: ["watch", "protocol", "phone"],
    emulator_storage_logs: true
  )

{:ok, session} =
  Emulator.launch(project_slug: "probe", platform: platform, artifact_path: pkg.artifact_path)

deadline = System.monotonic_time(:millisecond) + 120_000

:ok =
  Stream.repeatedly(fn ->
    case Emulator.ping(session.id) do
      {:ok, %{display_ready: true}} -> :ok
      _ -> :wait
    end
  end)
  |> Enum.find_value(fn
    :ok -> :ok
    :wait ->
      if System.monotonic_time(:millisecond) >= deadline, do
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

{:ok, ctx} = Emulator.log_capture_context(session.id)
log_task = Task.async(fn -> LogCapture.snapshot(ctx, duration_ms: 25_000) end)
{:ok, install} = Emulator.install(session.id)
Process.sleep(15_000)
snap = Task.await(log_task, 40_000)

stopped? =
  Enum.any?(snap.lines, fn line ->
    String.contains?(line, "AppRunState stop") and
      String.contains?(line, String.downcase(install.uuid))
  end)

IO.puts(
  "#{template} #{platform}: pbw=#{File.stat!(pkg.artifact_path).size} stopped=#{stopped?} app_log=#{snap.output =~ "AppLog"}"
)

Emulator.kill(session.id)
System.halt(if stopped?, do: 2, else: 0)
