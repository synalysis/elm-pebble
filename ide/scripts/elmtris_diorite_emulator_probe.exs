# Usage: cd ide && mix run scripts/elmtris_diorite_emulator_probe.exs
# Requires embedded emulator deps and ELMC_RUN_EMBEDDED_EMULATOR_LIVE=1 not needed.

Mix.Task.run("app.start")

alias Ide.Emulator
alias Ide.Emulator.LogCapture
alias Ide.ProjectTemplates
alias Ide.PebbleToolchain

unless Emulator.runtime_status("diorite").missing == [] do
  IO.puts("embedded emulator not ready: #{inspect(Emulator.runtime_status("diorite").missing)}")
  System.halt(1)
end

workspace = Path.join(System.tmp_dir!(), "elmtris_probe_#{System.unique_integer([:positive])}")
File.mkdir_p!(workspace)
:ok = ProjectTemplates.apply_template("game-elmtris", workspace)

project = %{
  slug: "elmtris-probe",
  name: "Elmtris Probe",
  target_type: "app",
  source_roots: ["watch", "protocol", "phone"]
}

gen = Path.join(workspace, "watch/.elmc-build/c/elmc_generated.c")

c =
  cond do
    File.exists?(gen) -> File.read!(gen)
    true ->
      alt = Path.join(workspace, ".pebble-sdk/app/src/c/elmc/c/elmc_generated.c")
      if File.exists?(alt), do: File.read!(alt), else: ""
  end

IO.puts("DefaultFont_calls=#{Regex.scan(~r/elmc_fn_Pebble_Ui_Resources_DefaultFont/, c) |> length()}")

pbw_path =
  case PebbleToolchain.package(project.slug,
         workspace_root: workspace,
         target_type: project.target_type,
         project_name: project.name,
         target_platforms: ["diorite"],
         source_roots: project.source_roots,
         emulator_storage_logs: true,
         emulator_agent_probes: true
       ) do
    {:ok, pkg} -> pkg.artifact_path
    {:error, reason} ->
      IO.puts("package failed: #{inspect(reason)}")
      System.halt(1)
  end

{:ok, session} =
  Emulator.launch(
    project_slug: project.slug,
    platform: "diorite",
    artifact_path: pbw_path
  )

session_id = session.id
IO.puts("session=#{session_id} pbw=#{pbw_path}")

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
      LogCapture.snapshot(ctx, duration_ms: 35_000)
    end)

  {:ok, install} = Emulator.install(session_id)
  IO.puts("installed uuid=#{install.uuid}")
  :ok = Emulator.request_app_logs(session_id)
  Process.sleep(20_000)

  snap = Task.await(log_task, 45_000)
  IO.puts("\n=== LOG SNAPSHOT fault=#{snap.fault_detected} ===\n")
  IO.puts(snap.output)
  IO.puts("\n=== END ===\n")

  stopped? =
    Enum.any?(snap.lines, fn line ->
      String.contains?(line, "AppRunState stop") and
        String.contains?(line, String.downcase(install.uuid))
    end)

  IO.puts("app_stopped_after_install=#{stopped?}")
  System.halt(if snap.fault_detected or stopped?, do: 2, else: 0)
after
  _ = Emulator.kill(session_id)
end
