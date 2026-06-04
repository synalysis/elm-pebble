defmodule IdeWeb.WorkspaceLive.EmulatorFlow do
  @moduledoc """
  Emulator pane LiveView events, async handlers, and screenshot gallery updates.

  Extracted from `WorkspaceLive`: install/stop/control, installation checks, captures,
  and `{:capture_all_progress, ...}` progress messages.
  """

  import Phoenix.Component, only: [assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [put_flash: 3, start_async: 3]

  alias Ide.Emulator
  alias Ide.EmulatorSupport
  alias Ide.PebbleToolchain
  alias Ide.Projects
  alias Ide.Projects.Project
  alias Ide.Screenshots
  alias IdeWeb.WorkspaceLive.BuildFlow
  alias IdeWeb.WorkspaceLive.DebuggerFlow
  alias IdeWeb.WorkspaceLive.PublishFlow
  alias IdeWeb.WorkspaceLive.ResourcesFlow
  alias IdeWeb.WorkspaceLive.ToolchainPresenter

  @type socket :: Phoenix.LiveView.Socket.t()
  @type lv_noreply :: {:noreply, socket()}
  @type wire_input :: String.t() | integer() | float() | boolean() | nil

  @emulator_events ~w(
    run-emulator-install
    stop-emulator
    toggle-external-emulator
    external-emulator-control
    refresh-emulator-installation
    install-emulator-dependencies
    capture-screenshot
    wasm-screenshot-saved
    capture-all-screenshots
    delete-screenshot
    delete-screenshot-target
    set-emulator-target
  )

  @emulator_asyncs [
    :check_emulator_installation,
    :install_emulator_dependencies,
    :run_emulator_install,
    :stop_emulator,
    :external_emulator_control,
    :capture_screenshot,
    :capture_all_screenshots
  ]

  @spec emulator_events() :: [String.t()]
  def emulator_events, do: @emulator_events

  @spec emulator_asyncs() :: [atom()]
  def emulator_asyncs, do: @emulator_asyncs

  @spec handles?(String.t()) :: boolean()
  def handles?(event) when is_binary(event), do: event in @emulator_events

  @spec handle_event(String.t(), map(), socket()) :: lv_noreply()
  def handle_event("run-emulator-install", _params, socket) do
    if external_emulator_blocked?(socket) do
      {:noreply, put_flash(socket, :error, external_emulator_disabled_message())}
    else
      project = socket.assigns.project
      emulator_target = socket.assigns.selected_emulator_target
      package_path = socket.assigns.publish_artifact_path
      workspace_root = Projects.project_workspace_path(project)

      {:noreply,
       socket
       |> assign(:pebble_install_status, :running)
       |> assign(:pebble_install_output, nil)
       |> start_async(:run_emulator_install, fn ->
         run_emulator_install_flow(
           project,
           workspace_root,
           emulator_target,
           package_path
         )
       end)}
    end
  end

  def handle_event("stop-emulator", _params, socket) do
    if external_emulator_blocked?(socket) do
      {:noreply, put_flash(socket, :error, external_emulator_disabled_message())}
    else
      project = socket.assigns.project

      {:noreply,
       socket
       |> assign(:emulator_stop_status, :running)
       |> assign(:emulator_stop_output, nil)
       |> start_async(:stop_emulator, fn ->
         PebbleToolchain.stop_emulator(project.slug, force: true)
       end)}
    end
  end

  def handle_event(
        "toggle-external-emulator",
        _params,
        %{assigns: %{external_emulator_running: true}} = socket
      ) do
    if external_emulator_blocked?(socket) do
      {:noreply, put_flash(socket, :error, external_emulator_disabled_message())}
    else
      __MODULE__.handle_event("stop-emulator", %{}, socket)
    end
  end

  def handle_event("toggle-external-emulator", _params, socket) do
    if external_emulator_blocked?(socket) do
      {:noreply, put_flash(socket, :error, external_emulator_disabled_message())}
    else
      __MODULE__.handle_event("run-emulator-install", %{}, socket)
    end
  end

  def handle_event("external-emulator-control", params, socket) do
    if external_emulator_blocked?(socket) do
      {:noreply, put_flash(socket, :error, external_emulator_disabled_message())}
    else
      project = socket.assigns.project
      emulator_target = socket.assigns.selected_emulator_target

      {:noreply,
       socket
       |> assign(:emulator_stop_status, :running)
       |> assign(:emulator_stop_output, nil)
       |> start_async(:external_emulator_control, fn ->
         PebbleToolchain.run_emulator_control(project.slug, emulator_target, params)
       end)}
    end
  end

  def handle_event("refresh-emulator-installation", _params, socket) do
    {:noreply, check_emulator_installation(socket)}
  end

  def handle_event("install-emulator-dependencies", _params, socket) do
    emulator_target = socket.assigns.selected_emulator_target

    {:noreply,
     socket
     |> assign(:emulator_dependency_install_status, :running)
     |> assign(:emulator_dependency_install_output, nil)
     |> start_async(:install_emulator_dependencies, fn ->
       Emulator.install_runtime_dependencies(emulator_target)
     end)}
  end

  def handle_event("capture-screenshot", _params, socket) do
    if external_emulator_blocked?(socket) do
      {:noreply, put_flash(socket, :error, external_emulator_disabled_message())}
    else
      project = socket.assigns.project
      emulator_target = socket.assigns.selected_emulator_target

      {:noreply,
       socket
       |> assign(:screenshot_status, :running)
       |> start_async(:capture_screenshot, fn ->
         Screenshots.capture(project, emulator_target: emulator_target)
       end)}
    end
  end

  def handle_event("wasm-screenshot-saved", %{"screenshot" => screenshot}, socket) do
    project = socket.assigns.project

    screenshots =
      socket.assigns.screenshots
      |> upsert_screenshot(atomize_screenshot(screenshot))

    readiness = PublishFlow.publish_readiness(project, screenshots)

    warnings =
      PublishFlow.publish_warnings(
        socket.assigns.project,
        readiness,
        socket.assigns.release_summary
      )

    {:noreply,
     socket
     |> assign(:screenshot_status, :ok)
     |> assign(:screenshots, screenshots)
     |> assign(:screenshot_groups, group_screenshots(screenshots))
     |> assign(:publish_readiness, readiness)
     |> assign(:publish_warnings, warnings)
     |> assign(
       :publish_summary,
       PublishFlow.publish_summary(socket.assigns.publish_checks, warnings, readiness)
     )
     |> assign(
       :publish_type_guidance,
       PublishFlow.publish_type_guidance(socket.assigns.project, readiness)
     )}
  end

  def handle_event("capture-all-screenshots", _params, socket) do
    project = socket.assigns.project
    workspace_root = Projects.project_workspace_path(project)
    package_path = socket.assigns.publish_artifact_path
    target_platforms = PublishFlow.target_platforms(project)
    token = System.unique_integer([:positive])
    lv = self()
    target_statuses = Enum.into(target_platforms, %{}, &{&1, "pending"})

    {:noreply,
     socket
     |> assign(:capture_all_status, :running)
     |> assign(:capture_all_token, token)
     |> assign(:capture_all_progress, "Starting screenshot capture...")
     |> assign(:capture_all_output, nil)
     |> assign(:capture_all_progress_lines, [])
     |> assign(:capture_all_target_statuses, target_statuses)
     |> start_async(:capture_all_screenshots, fn ->
       Screenshots.capture_all_targets(project,
         workspace_root: workspace_root,
         target_type: project.target_type,
         project_name: project.name,
         targets: target_platforms,
         package_path: package_path,
         close_emulator_afterwards: true,
         progress: fn msg -> send(lv, {:capture_all_progress, token, msg}) end
       )
     end)}
  end

  def handle_event(
        "delete-screenshot",
        %{"emulator-target" => emulator_target, "filename" => filename},
        socket
      ) do
    project = socket.assigns.project

    case Screenshots.delete(project, emulator_target, filename, []) do
      :ok ->
        screenshots = load_screenshots(project)
        readiness = PublishFlow.publish_readiness(project, screenshots)

        warnings =
          PublishFlow.publish_warnings(project, readiness, socket.assigns.release_summary)

        {:noreply,
         socket
         |> assign(:screenshots, screenshots)
         |> assign(:screenshot_groups, group_screenshots(screenshots))
         |> assign(:publish_readiness, readiness)
         |> assign(:publish_warnings, warnings)
         |> assign(
           :publish_summary,
           PublishFlow.publish_summary(socket.assigns.publish_checks, warnings, readiness)
         )
         |> put_flash(:info, "Deleted screenshot #{filename}.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not delete screenshot: #{inspect(reason)}")}
    end
  end

  def handle_event("delete-screenshot-target", %{"emulator-target" => emulator_target}, socket) do
    project = socket.assigns.project

    case Screenshots.delete_target(project, emulator_target, []) do
      :ok ->
        screenshots = load_screenshots(project)
        readiness = PublishFlow.publish_readiness(project, screenshots)

        warnings =
          PublishFlow.publish_warnings(project, readiness, socket.assigns.release_summary)

        {:noreply,
         socket
         |> assign(:screenshots, screenshots)
         |> assign(:screenshot_groups, group_screenshots(screenshots))
         |> assign(:publish_readiness, readiness)
         |> assign(:publish_warnings, warnings)
         |> assign(
           :publish_summary,
           PublishFlow.publish_summary(socket.assigns.publish_checks, warnings, readiness)
         )
         |> put_flash(:info, "Deleted all screenshots for #{emulator_target}.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not delete screenshots: #{inspect(reason)}")}
    end
  end

  def handle_event("set-emulator-target", %{"emulator" => params}, socket) do
    target = normalize_emulator_target(Map.get(params, "target"))
    mode = normalize_emulator_mode(target, Map.get(params, "mode"))

    project = persist_project_emulator_selection(socket.assigns.project, target, mode)

    {:noreply,
     socket
     |> assign(:project, project)
     |> assign(:selected_emulator_target, target)
     |> assign(:emulator_mode, mode)
     |> assign(:external_emulator_running, false)
     |> assign(:emulator_mode_options, ToolchainPresenter.emulator_mode_options(target))
     |> assign(:emulator_form, to_form(%{"target" => target, "mode" => mode}, as: :emulator))
     |> check_emulator_installation()}
  end

  defp do_handle_async(:check_emulator_installation, {:ok, status}, socket) do
    {:noreply, assign(socket, :emulator_installation_status, status)}
  end

  defp do_handle_async(:check_emulator_installation, {:exit, reason}, socket) do
    {:noreply,
     assign(socket, :emulator_installation_status, %{
       status: :error,
       components: [],
       missing: [],
       installable: false,
       error: "Emulator installation check exited: #{inspect(reason)}"
     })}
  end

  defp do_handle_async(:install_emulator_dependencies, {:ok, {:ok, result}}, socket) do
    {:noreply,
     socket
     |> assign(:emulator_dependency_install_status, result.after.status)
     |> assign(:emulator_dependency_install_output, result.output)
     |> assign(:emulator_installation_status, result.after)}
  end

  defp do_handle_async(:install_emulator_dependencies, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:emulator_dependency_install_status, :error)
     |> assign(
       :emulator_dependency_install_output,
       "Dependency install failed: #{inspect(reason)}"
     )
     |> check_emulator_installation()}
  end

  defp do_handle_async(:install_emulator_dependencies, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:emulator_dependency_install_status, :error)
     |> assign(
       :emulator_dependency_install_output,
       "Dependency install task exited: #{inspect(reason)}"
     )
     |> check_emulator_installation()}
  end

  defp do_handle_async(:run_emulator_install, {:ok, {:ok, result}}, socket) do
    socket =
      if is_binary(result[:artifact_path]) do
        assign(socket, :publish_artifact_path, result.artifact_path)
      else
        socket
      end

    {:noreply,
     socket
     |> assign(:pebble_install_status, result.status)
     |> assign(:external_emulator_running, result.status == :ok)
     |> assign(:pebble_install_output, ToolchainPresenter.render_toolchain_output(result))}
  end

  defp do_handle_async(:run_emulator_install, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:pebble_install_status, :error)
     |> assign(:external_emulator_running, false)
     |> assign(:pebble_install_output, emulator_install_error_message(reason))}
  end

  defp do_handle_async(:run_emulator_install, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:pebble_install_status, :error)
     |> assign(:external_emulator_running, false)
     |> assign(:pebble_install_output, "Emulator install task exited: #{inspect(reason)}")}
  end

  defp do_handle_async(:stop_emulator, {:ok, {:ok, result}}, socket) do
    {:noreply,
     socket
     |> assign(:emulator_stop_status, result.status)
     |> assign(:external_emulator_running, result.status != :ok)
     |> assign(:emulator_stop_output, ToolchainPresenter.render_toolchain_output(result))}
  end

  defp do_handle_async(:stop_emulator, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:emulator_stop_status, :error)
     |> assign(:emulator_stop_output, "Could not stop emulator: #{inspect(reason)}")}
  end

  defp do_handle_async(:stop_emulator, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:emulator_stop_status, :error)
     |> assign(:emulator_stop_output, "Emulator stop task exited: #{inspect(reason)}")}
  end

  defp do_handle_async(:external_emulator_control, {:ok, {:ok, :synced}}, socket) do
    {:noreply,
     socket
     |> assign(:emulator_stop_status, :ok)
     |> assign(:emulator_stop_output, "Simulator settings synced.")}
  end

  defp do_handle_async(:external_emulator_control, {:ok, {:ok, result}}, socket)
       when is_map(result) do
    {:noreply,
     socket
     |> assign(:emulator_stop_status, result.status)
     |> assign(:emulator_stop_output, ToolchainPresenter.render_toolchain_output(result))}
  end

  defp do_handle_async(:external_emulator_control, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:emulator_stop_status, :error)
     |> assign(:emulator_stop_output, "External emulator control failed: #{inspect(reason)}")}
  end

  defp do_handle_async(:external_emulator_control, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:emulator_stop_status, :error)
     |> assign(:emulator_stop_output, "External emulator control task exited: #{inspect(reason)}")}
  end

  defp do_handle_async(:capture_screenshot, {:ok, {:ok, result}}, socket) do
    project = socket.assigns.project
    screenshots = load_screenshots(project)
    readiness = PublishFlow.publish_readiness(project, screenshots)

    warnings =
      PublishFlow.publish_warnings(
        socket.assigns.project,
        readiness,
        socket.assigns.release_summary
      )

    {:noreply,
     socket
     |> assign(:screenshot_status, :ok)
     |> assign(:screenshots, screenshots)
     |> assign(:screenshot_groups, group_screenshots(screenshots))
     |> assign(:publish_readiness, readiness)
     |> assign(:publish_warnings, warnings)
     |> assign(
       :publish_summary,
       PublishFlow.publish_summary(socket.assigns.publish_checks, warnings, readiness)
     )
     |> assign(
       :publish_type_guidance,
       PublishFlow.publish_type_guidance(socket.assigns.project, readiness)
     )
     |> assign(:screenshot_output, ToolchainPresenter.render_screenshot_output(result))}
  end

  defp do_handle_async(:capture_screenshot, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:screenshot_status, :error)
     |> assign(:screenshot_output, "Screenshot failed before execution: #{inspect(reason)}")}
  end

  defp do_handle_async(:capture_screenshot, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:screenshot_status, :error)
     |> assign(:screenshot_output, "Screenshot task exited: #{inspect(reason)}")}
  end

  defp do_handle_async(:capture_all_screenshots, {:ok, {:ok, result}}, socket) do
    project = socket.assigns.project
    screenshots = load_screenshots(project)
    readiness = PublishFlow.publish_readiness(project, screenshots)

    warnings =
      PublishFlow.publish_warnings(
        socket.assigns.project,
        readiness,
        socket.assigns.release_summary
      )

    target_statuses =
      merge_capture_all_result_statuses(socket.assigns.capture_all_target_statuses || %{}, result)

    {:noreply,
     socket
     |> assign(:capture_all_status, :ok)
     |> assign(:screenshots, screenshots)
     |> assign(:screenshot_groups, group_screenshots(screenshots))
     |> assign(:publish_readiness, readiness)
     |> assign(:publish_warnings, warnings)
     |> assign(
       :publish_summary,
       PublishFlow.publish_summary(socket.assigns.publish_checks, warnings, readiness)
     )
     |> assign(
       :publish_type_guidance,
       PublishFlow.publish_type_guidance(socket.assigns.project, readiness)
     )
     |> assign(:capture_all_progress, "Capture complete.")
     |> assign(:capture_all_target_statuses, target_statuses)
     |> assign(:capture_all_output, ToolchainPresenter.render_capture_all_output(result))}
  end

  defp do_handle_async(:capture_all_screenshots, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:capture_all_status, :error)
     |> assign(:capture_all_progress, nil)
     |> assign(:capture_all_output, "Capture-all failed: #{inspect(reason)}")}
  end

  defp do_handle_async(:capture_all_screenshots, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:capture_all_status, :error)
     |> assign(:capture_all_progress, nil)
     |> assign(:capture_all_output, "Capture-all task exited: #{inspect(reason)}")}
  end

  def handle_info({:capture_all_progress, token, msg}, socket) do
    if socket.assigns.capture_all_token == token do
      line = render_capture_all_progress(msg)

      lines =
        (socket.assigns.capture_all_progress_lines || [])
        |> Kernel.++([line])
        |> Enum.take(-300)

      target_statuses =
        update_capture_target_statuses(socket.assigns.capture_all_target_statuses || %{}, msg)

      socket =
        socket
        |> assign(:capture_all_progress, line)
        |> assign(:capture_all_progress_lines, lines)
        |> assign(:capture_all_target_statuses, target_statuses)
        |> assign(:capture_all_output, Enum.join(lines, "\n"))
        |> maybe_merge_capture_progress_screenshot(msg)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def maybe_check_emulator_installation(socket) do
    if socket.assigns[:live_action] == :emulator do
      check_emulator_installation(socket)
    else
      socket
    end
  end

  @spec check_emulator_installation(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def check_emulator_installation(socket) do
    emulator_target = socket.assigns[:selected_emulator_target] || default_emulator_target()

    socket
    |> assign(:emulator_installation_status, %{
      status: :checking,
      platform: emulator_target,
      components: [],
      missing: [],
      installable: false
    })
    |> start_async(:check_emulator_installation, fn ->
      Emulator.runtime_status(emulator_target)
    end)
  end

  @spec persist_project_emulator_selection(Project.t(), String.t(), String.t()) :: Project.t()
  def persist_project_emulator_selection(%Project{} = project, target, mode) do
    selected_target = normalize_emulator_target(target)
    selected_mode = normalize_emulator_mode(selected_target, mode)
    settings = project.debugger_settings || %{}

    updated_settings =
      settings
      |> Map.put("emulator_target", selected_target)
      |> Map.put("emulator_mode", selected_mode)
      |> Map.put(
        "watch_profile_id",
        DebuggerFlow.normalize_debugger_watch_profile_id(selected_target)
      )

    case Projects.update_project(project, %{"debugger_settings" => updated_settings}) do
      {:ok, updated} -> updated
      {:error, _} -> project
    end
  end

  def persist_project_emulator_selection(project, _target, _mode), do: project

  @spec project_emulator_target(Project.t()) :: String.t()
  def project_emulator_target(%Project{} = project) do
    settings = project.debugger_settings || %{}
    normalize_emulator_target(Map.get(settings, "emulator_target"))
  end

  @spec project_emulator_mode(Project.t()) :: String.t()
  def project_emulator_mode(%Project{} = project) do
    settings = project.debugger_settings || %{}
    target = project_emulator_target(project)
    normalize_emulator_mode(target, Map.get(settings, "emulator_mode"))
  end

  def atomize_screenshot(screenshot) when is_map(screenshot) do
    %{
      filename: Map.get(screenshot, "filename") || Map.get(screenshot, :filename),
      emulator_target:
        Map.get(screenshot, "emulator_target") || Map.get(screenshot, :emulator_target),
      url: Map.get(screenshot, "url") || Map.get(screenshot, :url),
      absolute_path: Map.get(screenshot, "absolute_path") || Map.get(screenshot, :absolute_path),
      captured_at: Map.get(screenshot, "captured_at") || Map.get(screenshot, :captured_at)
    }
  end

  def default_emulator_target do
    Application.get_env(:ide, Ide.PebbleToolchain, [])
    |> Keyword.get(:emulator_target, "basalt")
  end

  @spec normalize_emulator_target(wire_input()) :: String.t()
  def normalize_emulator_target(target), do: EmulatorSupport.normalize_target(target)

  @spec normalize_emulator_mode(String.t() | nil, wire_input()) :: String.t()
  def normalize_emulator_mode(target, mode), do: EmulatorSupport.normalize_mode(target, mode)

  def external_emulator_blocked?(socket) do
    socket.assigns.emulator_mode == "external" and not EmulatorSupport.external_mode_enabled?()
  end

  def external_emulator_disabled_message do
    "External Pebble emulator is not available on this hosted IDE. Use Embedded or WASM instead."
  end

  def group_screenshots(shots), do: ResourcesFlow.group_screenshots(shots)

  @type capture_progress ::
          Screenshots.progress_payload()
          | {:target, String.t(), :captured, Screenshots.screenshot()}
          | {:close, {:ok, map()} | {:error, String.t() | atom() | map()}}
  @type target_statuses :: %{String.t() => String.t()}
  @type screenshot_row :: Screenshots.screenshot() | map()
  @type screenshot_identity ::
          {:path, String.t()} | {:filename, String.t()} | {:fallback, String.t()}
  @type screenshot_sort_key :: integer() | String.t()
  @type install_error :: atom() | tuple() | String.t()

  @spec render_capture_all_progress(capture_progress()) :: String.t()
  def render_capture_all_progress({:phase, message}) when is_binary(message), do: message

  def render_capture_all_progress({:target, target, :cleanup_before}),
    do: "[#{target}] Cleaning previous emulator..."

  def render_capture_all_progress({:target, target, :installing}),
    do: "[#{target}] Installing app..."

  def render_capture_all_progress({:target, target, :capturing}),
    do: "[#{target}] Capturing screenshot..."

  def render_capture_all_progress({:target, target, :capture_attempt, attempt, total}),
    do: "[#{target}] Capture attempt #{attempt}/#{total}..."

  def render_capture_all_progress({:target, target, :capture_retry, attempt, total, reason}),
    do: "[#{target}] Attempt #{attempt}/#{total} failed: #{inspect(reason)}"

  def render_capture_all_progress({:target, target, :ok}), do: "[#{target}] Screenshot captured."

  def render_capture_all_progress({:target, target, :captured, _screenshot}),
    do: "[#{target}] Screenshot added to gallery."

  def render_capture_all_progress({:target, target, :cleanup_after}),
    do: "[#{target}] Closing emulator..."

  def render_capture_all_progress({:target, target, :cleanup_error, _phase, reason}),
    do: "[#{target}] Cleanup warning: #{inspect(reason)}"

  def render_capture_all_progress({:target, target, :error, reason}),
    do: "[#{target}] Failed: #{inspect(reason)}"

  def render_capture_all_progress({:close, {:ok, _result}}), do: "Emulators stopped."

  def render_capture_all_progress({:close, {:error, reason}}),
    do: "Could not stop emulators: #{inspect(reason)}"

  def render_capture_all_progress(_), do: "Working..."

  @spec update_capture_target_statuses(target_statuses(), capture_progress()) ::
          target_statuses()
  def update_capture_target_statuses(statuses, {:target, target, :cleanup_before}),
    do: Map.put(statuses, target, "cleaning previous emulator")

  def update_capture_target_statuses(statuses, {:target, target, :installing}),
    do: Map.put(statuses, target, "installing")

  def update_capture_target_statuses(statuses, {:target, target, :capturing}),
    do: Map.put(statuses, target, "capturing")

  def update_capture_target_statuses(
        statuses,
        {:target, target, :capture_attempt, attempt, total}
      ),
      do: Map.put(statuses, target, "capture attempt #{attempt}/#{total}")

  def update_capture_target_statuses(
        statuses,
        {:target, target, :capture_retry, attempt, total, _reason}
      ),
      do: Map.put(statuses, target, "retrying after attempt #{attempt}/#{total}")

  def update_capture_target_statuses(statuses, {:target, target, :ok}),
    do: Map.put(statuses, target, "done")

  def update_capture_target_statuses(statuses, {:target, target, :cleanup_after}),
    do: keep_capture_terminal_status(statuses, target, "closing emulator")

  def update_capture_target_statuses(
        statuses,
        {:target, target, :cleanup_error, _phase, reason}
      ),
      do: keep_capture_terminal_status(statuses, target, "cleanup warning: #{inspect(reason)}")

  def update_capture_target_statuses(statuses, {:target, target, :error, reason}),
    do: Map.put(statuses, target, "error: #{inspect(reason)}")

  def update_capture_target_statuses(statuses, {:phase, message}) when is_binary(message) do
    case Regex.run(~r/^\[(\d+)\/(\d+)\]\s+([a-z0-9_-]+)/i, message) do
      [_, _idx, _total, target] -> Map.put(statuses, target, "running")
      _ -> statuses
    end
  end

  def update_capture_target_statuses(statuses, _msg), do: statuses

  @spec maybe_merge_capture_progress_screenshot(socket(), capture_progress()) :: socket()
  def maybe_merge_capture_progress_screenshot(socket, {:target, _target, :captured, screenshot})
      when is_map(screenshot) do
    shots = upsert_screenshot(socket.assigns.screenshots || [], screenshot)

    socket
    |> assign(:screenshots, shots)
    |> assign(:screenshot_groups, group_screenshots(shots))
  end

  def maybe_merge_capture_progress_screenshot(socket, _msg), do: socket

  @spec upsert_screenshot([screenshot_row()], screenshot_row()) :: [screenshot_row()]
  def upsert_screenshot(existing, screenshot) do
    key = screenshot_identity(screenshot)

    existing
    |> Enum.reject(fn item -> screenshot_identity(item) == key end)
    |> Kernel.++([screenshot])
    |> Enum.sort_by(&screenshot_sort_key/1, :desc)
  end

  @spec screenshot_identity(screenshot_row()) :: screenshot_identity()
  def screenshot_identity(item) when is_map(item) do
    cond do
      is_binary(item[:absolute_path]) and item[:absolute_path] != "" ->
        {:path, item[:absolute_path]}

      is_binary(item[:filename]) and item[:filename] != "" ->
        {:filename, item[:filename]}

      true ->
        {:fallback, inspect(item)}
    end
  end

  @spec screenshot_sort_key(screenshot_row()) :: screenshot_sort_key()
  def screenshot_sort_key(item) when is_map(item) do
    case item[:captured_at] do
      %DateTime{} = dt -> DateTime.to_unix(dt, :microsecond)
      %NaiveDateTime{} = dt -> NaiveDateTime.to_iso8601(dt)
      other when is_binary(other) -> other
      _ -> ""
    end
  end

  @spec keep_capture_terminal_status(target_statuses(), String.t(), String.t()) ::
          target_statuses()
  def keep_capture_terminal_status(statuses, target, next_status) do
    case Map.get(statuses, target) do
      "done" -> statuses
      "error: " <> _ = error_status -> Map.put(statuses, target, error_status)
      _ -> Map.put(statuses, target, next_status)
    end
  end

  @spec merge_capture_all_result_statuses(
          target_statuses(),
          Screenshots.capture_all_result() | map()
        ) ::
          target_statuses()
  def merge_capture_all_result_statuses(statuses, result) when is_map(result) do
    results = Map.get(result, :results, [])

    Enum.reduce(results, statuses, fn
      {target, {:ok, _shot}}, acc ->
        Map.put(acc, target, "done")

      {target, {:error, reason}}, acc ->
        Map.put(acc, target, "error: #{inspect(reason)}")

      _other, acc ->
        acc
    end)
  end

  def merge_capture_all_result_statuses(statuses, _result), do: statuses

  @spec emulator_install_error_message(install_error()) :: String.t()
  def emulator_install_error_message(:package_path_required) do
    "No installable artifact selected. Generate a `.pbw` artifact first, then install it to the emulator."
  end

  def emulator_install_error_message({:package_path_not_found, path}) do
    "Selected artifact was not found: #{path}"
  end

  def emulator_install_error_message({:package_path_not_pbw, path}) do
    "Selected artifact is not a `.pbw` file: #{path}"
  end

  def emulator_install_error_message(reason) do
    "Emulator install failed before execution: #{inspect(reason)}"
  end

  @spec handle_async(atom(), term(), socket()) :: lv_noreply()
  def handle_async(async, result, socket) when async in @emulator_asyncs do
    do_handle_async(async, result, socket)
  end

  def handle_async(_async, _result, socket), do: {:noreply, socket}

  defdelegate run_emulator_install_flow(project, workspace_root, emulator_target, package_path),
    to: BuildFlow

  defdelegate load_screenshots(project), to: ResourcesFlow
end
