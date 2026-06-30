# Usage:
#   cd ide && mix run scripts/template_emulator_gate.exs
#   TEMPLATE_FILTER=watchface-yes,starter mix run scripts/template_emulator_gate.exs
#
# Runs each IDE project template through the embedded Pebble emulator:
# package → launch → display ready → install → log capture → fault check.

Mix.Task.run("app.start")

alias Ide.Emulator
alias Ide.Emulator.LogCapture
alias Ide.Emulator.Workflow
alias Ide.PebbleToolchain
alias Ide.ProjectTemplates

button_protocol = 8
button_select_mask = 4
display_wait_ms = 120_000
log_capture_ms = 18_000
post_install_sleep_ms = 12_000

format_error = fn
  {:fault, output} -> "App fault\n#{String.slice(output, 0, 800)}"
  {:stopped, output} -> "App stopped after install\n#{String.slice(output, 0, 800)}"
  {:exception, message} -> "exception: #{message}"
  reason -> inspect(reason)
end

app_stopped_after_install? = fn lines, uuid ->
  down = String.downcase(uuid)

  Enum.any?(lines, fn line ->
    String.contains?(line, "AppRunState stop") and String.contains?(line, down)
  end)
end

screenshot_size = fn session_id ->
  case Emulator.screenshot(session_id, []) do
    {:ok, png} when is_binary(png) -> byte_size(png)
    _ -> 0
  end
end

open_from_launcher = fn session_id ->
  for state <- [button_select_mask, 0] do
    _ = Emulator.control(session_id, button_protocol, <<state>>)
    Process.sleep(150)
  end

  :ok
end

run_template = fn template ->
  workspace =
    Path.join(
      System.tmp_dir!(),
      "emu-gate-#{template}-#{System.unique_integer([:positive])}"
    )

  platform = ProjectTemplates.target_platforms_for_template(template) |> List.first("basalt")
  target_type = ProjectTemplates.target_type_for_template(template)
  slug = "emu-gate-#{template}"

  IO.puts("[#{template}] platform=#{platform} target=#{target_type}")

  try do
    with :ok <- ProjectTemplates.apply_template(template, workspace),
         {:ok, pkg} <-
           PebbleToolchain.package(slug,
             workspace_root: workspace,
             target_type: target_type,
             project_name: template,
             target_platforms: [platform]
           ),
         {:ok, session} <-
           Emulator.launch(
             project_slug: slug,
             platform: platform,
             artifact_path: pkg.artifact_path,
             has_phone_companion: Map.get(pkg, :has_phone_companion, false),
             has_companion_preferences: Map.get(pkg, :has_companion_preferences, false)
           ) do
      session_id = session.id

      try do
        with :ok <- Workflow.wait_display_ready(session_id, timeout_ms: display_wait_ms),
             {:ok, ctx} <- Emulator.log_capture_context(session_id),
             log_task <- Task.async(fn -> LogCapture.snapshot(ctx, duration_ms: log_capture_ms) end),
             {:ok, install} <- Emulator.install(session_id),
             :ok <- if(target_type == "watchface", do: :ok, else: open_from_launcher.(session_id)),
             :ok <- Emulator.request_app_logs(session_id) do
          Process.sleep(post_install_sleep_ms)
          snap = Task.await(log_task, log_capture_ms + 15_000)

          cond do
            snap.fault_detected ->
              {:error, {:fault, snap.output}}

            app_stopped_after_install?.(snap.lines, install.uuid) ->
              {:error, {:stopped, snap.output}}

            true ->
              {:ok,
               %{
                 platform: platform,
                 uuid: install.uuid,
                 screenshot_bytes: screenshot_size.(session_id),
                 log_lines: length(snap.lines)
               }}
          end
        else
          {:error, reason} -> {:error, reason}
          :timeout -> {:error, :display_timeout}
          other -> {:error, other}
        end
      after
        _ = Emulator.kill(session_id)
      end
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  rescue
    error -> {:error, {:exception, Exception.message(error)}}
  after
    File.rm_rf(workspace)
  end
end

status = Emulator.runtime_status("basalt")

if status.missing != [] do
  IO.puts("embedded emulator not ready: #{inspect(status.missing)}")
  System.halt(1)
end

templates =
  case System.get_env("TEMPLATE_FILTER") do
    nil ->
      ProjectTemplates.template_keys()

    raw ->
      raw
      |> String.split([",", " "], trim: true)
      |> Enum.filter(&(&1 in ProjectTemplates.template_keys()))
  end

IO.puts("template emulator gate: #{length(templates)} template(s)")
IO.puts("")

results = Enum.map(templates, fn template -> {template, run_template.(template)} end)

{ok, failed} = Enum.split_with(results, fn {_t, r} -> match?({:ok, _}, r) end)

IO.puts("\n=== SUMMARY ===")
IO.puts("ok: #{length(ok)}  failed: #{length(failed)}")

for {template, {:error, reason}} <- failed do
  IO.puts("  FAIL #{template}: #{format_error.(reason)}")
end

for {template, {:ok, meta}} <- ok do
  IO.puts("  OK   #{template} (#{meta.platform}, screenshot=#{meta.screenshot_bytes}B)")
end

System.halt(if failed == [], do: 0, else: 1)
