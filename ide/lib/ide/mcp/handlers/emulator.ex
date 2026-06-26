defmodule Ide.Mcp.Handlers.Emulator do
  @moduledoc false

  alias Ide.Emulator
  alias Ide.Emulator.LogCapture
  alias Ide.Emulator.Types, as: EmulatorTypes
  alias Ide.Emulator.Workflow
  alias Ide.Mcp.ToolTypes
  alias Ide.Mcp.ToolSupport
  alias Ide.Mcp.WireTypes
  alias Ide.PebbleToolchain
  alias Ide.Projects
  alias Ide.WatchModels

  def call("emulator.launch", %{"slug" => slug} = args) do
    with {:ok, project} <- ToolSupport.fetch_project(slug),
         {:ok, platform} <- resolve_platform(args, project),
         {:ok, launched} <- Workflow.launch_project(project, platform),
         :ok <- maybe_wait_display_ready(launched.session.id, args) do
      {:ok, launch_payload(slug, launched)}
    else
      {:error, :project_not_found} ->
        {:error, "project not found: #{slug}"}

      {:error, reason} ->
        {:error, "embedded emulator launch failed: #{format_run_error(reason)}"}
    end
  end

  def call("emulator.install", %{"session_id" => session_id} = args) do
    with :ok <- maybe_wait_display_ready(session_id, args),
         {:ok, result} <- Emulator.install(session_id) do
      {:ok,
       %{
         session_id: session_id,
         status: "ok",
         install_result: result,
         logs: logs_payload(capture_logs_snapshot(session_id, args))
       }}
    else
      {:error, reason} ->
        {:error, "embedded emulator install failed: #{Workflow.install_error_message(reason)}"}
    end
  end

  def call("emulator.ping", %{"session_id" => session_id}) do
    case Emulator.ping(session_id) do
      {:ok, info} ->
        {:ok, %{session_id: session_id, alive: true, session: info}}

      {:error, reason} ->
        {:ok, %{session_id: session_id, alive: false, error: inspect(reason)}}
    end
  end

  def call("emulator.kill", %{"session_id" => session_id}) do
    :ok = Emulator.kill(session_id)
    {:ok, %{session_id: session_id, status: "ok"}}
  end

  def call("emulator.logs", %{"session_id" => session_id} = args) do
    snapshot = capture_logs_snapshot(session_id, args)

    {:ok,
     %{
       session_id: session_id,
       logs: logs_payload(snapshot)
     }}
  end

  def call("emulator.run", %{"slug" => slug} = args) do
    install? = ToolSupport.normalize_mcp_boolean(Map.get(args, "install"), true)
    kill_after? = ToolSupport.normalize_mcp_boolean(Map.get(args, "kill_after"), true)
    boot_wait_ms = parse_boot_wait_ms(Map.get(args, "boot_wait_ms"))

    with {:ok, project} <- ToolSupport.fetch_project(slug),
         {:ok, platform} <- resolve_platform(args, project),
         {:ok, launched} <- Workflow.launch_project(project, platform) do
      run_launched_session(slug, launched, args, install?, kill_after?, boot_wait_ms)
    else
      {:error, :project_not_found} ->
        {:error, "project not found: #{slug}"}

      {:error, reason} ->
        {:error, "embedded emulator run failed: #{format_run_error(reason)}"}
    end
  end

  def call(name, _args), do: {:error, "unknown emulator tool: #{name}"}

  @spec run_launched_session(String.t(), Workflow.launch_result(), ToolTypes.tool_args(), boolean(), boolean(), non_neg_integer()) ::
          {:ok, ToolTypes.emulator_run_result()} | {:error, String.t()}
  defp run_launched_session(slug, launched, args, install?, kill_after?, boot_wait_ms) do
    session_id = launched.session.id
    args = Map.put_new(args, "logs_snapshot_seconds", 20)

    try do
      result =
        with :ok <- wait_display_ready(session_id, args) do
          log_task = start_log_capture_task(session_id, args)

          with {:ok, install_result} <- run_optional_install(session_id, install?, args),
               :ok <- Emulator.request_app_logs(session_id),
               :ok <- maybe_boot_wait(boot_wait_ms),
               :ok <- maybe_open_from_launcher(session_id, args),
               {:ok, snapshot} <- finish_log_capture_task(log_task) do
            {:ok,
             %{
               slug: slug,
               platform: launched.platform,
               artifact_path: launched.artifact_path,
               session: launched.session,
               installed: install?,
               install_result: install_result,
               logs: logs_payload(snapshot),
               fault_detected: snapshot.fault_detected,
               session_killed: kill_after?
             }}
          end
        end

      case result do
        {:ok, payload} -> {:ok, payload}
        {:error, reason} -> {:error, "embedded emulator run failed: #{format_run_error(reason)}"}
      end
    after
      if kill_after? do
        :ok = Emulator.kill(session_id)
      end
    end
  end

  @spec launch_payload(String.t(), Workflow.launch_result()) :: ToolTypes.emulator_launch_payload()
  defp launch_payload(slug, %{session: session, artifact_path: artifact_path, platform: platform}) do
    %{
      slug: slug,
      platform: platform,
      artifact_path: artifact_path,
      session: session
    }
  end

  @spec resolve_platform(ToolTypes.tool_args(), Projects.Project.t()) ::
          {:ok, String.t()} | {:error, EmulatorTypes.unsupported_emulator_target()}
  defp resolve_platform(args, project) do
    case Map.get(args, "platform") || Map.get(args, "emulator_target") do
      platform when is_binary(platform) ->
        platform = String.trim(platform)

        if platform == "" do
          {:ok, default_platform(project)}
        else
          validate_platform(platform)
        end

      _ ->
        {:ok, default_platform(project)}
    end
  end

  @spec default_platform(Projects.Project.t()) :: String.t()
  defp default_platform(project) do
    project
    |> Map.get(:debugger_settings, %{})
    |> Map.get("emulator_target")
    |> case do
      platform when is_binary(platform) ->
        platform = String.trim(platform)
        if platform == "", do: WatchModels.default_id(), else: platform

      _ ->
        WatchModels.default_id()
    end
  end

  @spec validate_platform(String.t()) ::
          {:ok, String.t()} | {:error, EmulatorTypes.unsupported_emulator_target()}
  defp validate_platform(platform) do
    allowed = PebbleToolchain.supported_emulator_targets()

    if platform in allowed do
      {:ok, platform}
    else
      {:error, {:unsupported_emulator_target, platform, allowed}}
    end
  end

  @spec maybe_wait_display_ready(String.t(), ToolTypes.tool_args()) ::
          :ok | {:error, EmulatorTypes.display_ready_error()}
  defp maybe_wait_display_ready(session_id, args) do
    if wait_display_ready?(args) do
      wait_display_ready(session_id, args)
    else
      :ok
    end
  end

  @spec wait_display_ready(String.t(), ToolTypes.tool_args()) ::
          :ok | {:error, EmulatorTypes.display_ready_error()}
  defp wait_display_ready(session_id, args) do
    Workflow.wait_display_ready(session_id, timeout_ms: parse_display_ready_timeout_ms(args))
  end

  @spec wait_display_ready?(ToolTypes.tool_args()) :: boolean()
  defp wait_display_ready?(args) do
    ToolSupport.normalize_mcp_boolean(Map.get(args, "wait_display_ready"), true)
  end

  @spec run_optional_install(String.t(), boolean(), ToolTypes.tool_args()) ::
          {:ok, EmulatorTypes.pbw_install_result() | nil} | {:error, EmulatorTypes.session_error()}
  defp run_optional_install(_session_id, false, _args), do: {:ok, nil}

  defp run_optional_install(session_id, true, _args) do
    case Emulator.install(session_id) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec maybe_boot_wait(non_neg_integer()) :: :ok
  defp maybe_boot_wait(0), do: :ok

  defp maybe_boot_wait(ms) when is_integer(ms) and ms > 0 do
    Process.sleep(ms)
    :ok
  end

  @button_protocol 8
  @button_select_mask 4
  @spec start_log_capture_task(String.t(), ToolTypes.tool_args()) :: Task.t()
  defp start_log_capture_task(session_id, args) do
    context =
      case Emulator.log_capture_context(session_id) do
        {:ok, ctx} -> ctx
        _ -> %{console_port: nil, protocol_router_pid: nil}
      end

    Task.async(fn -> capture_logs_snapshot(context, args) end)
  end

  @spec finish_log_capture_task(Task.t()) :: {:ok, Ide.Emulator.LogCapture.snapshot()}
  defp finish_log_capture_task(task) do
    {:ok, Task.await(task, log_capture_task_timeout_ms())}
  catch
    :exit, _ ->
      {:ok,
       %{
         source: "embedded",
         duration_ms: 0,
         output: "log capture task failed",
         lines: [],
         fault_detected: false,
         console: %{output: "", error: :timeout},
         protocol: %{lines: [], error: :timeout}
       }}
  end

  @spec log_capture_task_timeout_ms() :: pos_integer()
  defp log_capture_task_timeout_ms, do: 40_000

  @spec capture_logs_snapshot(LogCapture.capture_context(), ToolTypes.tool_args()) ::
          LogCapture.snapshot()
  defp capture_logs_snapshot(context, args) when is_map(context) do
    seconds = Map.get(args, "logs_snapshot_seconds")

    opts =
      if is_nil(seconds) do
        [duration_ms: 5_000]
      else
        [logs_snapshot_seconds: parse_logs_snapshot_seconds(seconds)]
      end

    LogCapture.snapshot(context, opts)
  end

  @spec capture_logs_snapshot(String.t(), ToolTypes.tool_args()) :: LogCapture.snapshot()
  defp capture_logs_snapshot(session_id, args) when is_binary(session_id) do
    case Emulator.log_capture_context(session_id) do
      {:ok, context} -> capture_logs_snapshot(context, args)
      _ -> LogCapture.snapshot(%{}, [])
    end
  end

  @spec logs_payload(LogCapture.snapshot()) :: ToolTypes.emulator_logs_payload()
  defp logs_payload(snapshot) do
    %{
      source: snapshot.source,
      duration_ms: snapshot.duration_ms,
      output: snapshot.output,
      lines: snapshot.lines,
      fault_detected: snapshot.fault_detected,
      console: snapshot.console,
      protocol: snapshot.protocol
    }
  end

  @spec maybe_open_from_launcher(String.t(), ToolTypes.tool_args()) :: :ok
  defp maybe_open_from_launcher(session_id, args) do
    if ToolSupport.normalize_mcp_boolean(Map.get(args, "open_from_launcher"), false) do
      press_select_button(session_id)
    end

    :ok
  end

  @spec press_select_button(String.t()) :: :ok
  defp press_select_button(session_id) do
    for state <- [@button_select_mask, 0] do
      _ = Emulator.control(session_id, @button_protocol, <<state>>)
      Process.sleep(150)
    end

    :ok
  end

  @type run_error ::
          EmulatorTypes.unsupported_emulator_target()
          | Workflow.launch_error()
          | Workflow.install_error_input()

  @spec format_run_error(run_error()) :: String.t()
  defp format_run_error({:unsupported_emulator_target, platform, allowed}) do
    "unsupported emulator target #{inspect(platform)}; allowed: #{Enum.join(allowed, ", ")}"
  end

  defp format_run_error(reason) do
    launch = Workflow.launch_error_message(reason)

    if launch != inspect(reason) do
      launch
    else
      Workflow.install_error_message(reason)
    end
  end

  @spec parse_display_ready_timeout_ms(ToolTypes.tool_args()) :: pos_integer()
  defp parse_display_ready_timeout_ms(args) do
    parse_positive_ms(Map.get(args, "display_ready_timeout_ms"), 120_000, 600_000)
  end

  @spec parse_boot_wait_ms(WireTypes.integer_input()) :: non_neg_integer()
  defp parse_boot_wait_ms(value), do: parse_positive_ms(value, 0, 60_000)

  @spec parse_positive_ms(WireTypes.integer_input(), non_neg_integer(), pos_integer()) ::
          non_neg_integer()
  defp parse_positive_ms(value, _default, max) when is_integer(value) and value >= 0 do
    min(value, max)
  end

  defp parse_positive_ms(value, default, max) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} when parsed >= 0 -> min(parsed, max)
      _ -> default
    end
  end

  defp parse_positive_ms(_value, default, _max), do: default

  @spec parse_logs_snapshot_seconds(WireTypes.integer_input()) :: pos_integer()
  defp parse_logs_snapshot_seconds(value) when is_integer(value) and value >= 1 do
    min(value, 30)
  end

  defp parse_logs_snapshot_seconds(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} when parsed >= 1 -> min(parsed, 30)
      _ -> 4
    end
  end

  defp parse_logs_snapshot_seconds(_), do: 4
end
