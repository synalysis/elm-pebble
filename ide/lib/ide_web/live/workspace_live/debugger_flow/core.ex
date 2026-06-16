defmodule IdeWeb.WorkspaceLive.DebuggerFlow.Core do
  @moduledoc false

  import Phoenix.Component
  import Phoenix.LiveView

  alias Ide.Emulator.QemuControl
  alias Ide.EmulatorSupport
  alias Ide.PebbleToolchain
  alias Ide.Projects
  alias Ide.Projects.Project
  alias Ide.SimulatorSettings
  alias IdeWeb.WorkspaceLive.BuildFlow
  alias IdeWeb.WorkspaceLive.DebuggerBootstrapFlow
  alias IdeWeb.WorkspaceLive.DebuggerSupport
  alias IdeWeb.WorkspaceLive.EditorSupport
  alias IdeWeb.WorkspaceLive.Types

  @type socket :: Phoenix.LiveView.Socket.t()
  @type lv_noreply :: {:noreply, socket()}
  @type wire_input :: String.t() | integer() | boolean() | nil

  @debugger_auto_fire_refresh_interval_ms 1_000
  @debugger_auto_fire_min_refresh_interval_ms 100

  @spec handle_simulator_save_settings_event(map(), socket()) :: {:noreply, socket()}
  def handle_simulator_save_settings_event(params, socket) when is_map(params) do
    values =
      Map.get(params, "simulator") || Map.get(params, "debugger_simulator") || %{}

    handle_simulator_save_settings(socket, values)
  end

  def handle_event("debugger-start", _params, socket) do
    cond do
      is_nil(socket.assigns.project) ->
        {:noreply, socket}

      socket.assigns[:debugger_bootstrap_status] == :running ->
        {:noreply, socket}

      true ->
        {:noreply, begin_debugger_bootstrap(socket, socket.assigns.project)}
    end
  end

  def handle_event("debugger-set-timeline-mode", %{"mode" => mode}, socket) do
    mode =
      normalize_project_debugger_timeline_mode(
        mode,
        Map.get(socket.assigns, :companion_app_present, false)
      )

    socket = DebuggerSupport.set_debugger_timeline_mode(socket, mode)

    case socket.assigns.project do
      %Project{} = project ->
        project =
          persist_project_debugger_timeline_mode(
            project,
            socket.assigns.debugger_timeline_mode
          )

        {:noreply, assign(socket, :project, project)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("debugger-set-auto-fire", params, socket) do
    case socket.assigns.project do
      nil ->
        {:noreply, socket}

      project ->
        attrs = %{
          target: Map.get(params, "target"),
          trigger: Map.get(params, "trigger"),
          enabled: Map.get(params, "enabled")
        }

        project = persist_project_auto_fire_setting(project, attrs)
        {:ok, _state} = Ide.Debugger.set_auto_fire(Projects.scope_key(project), attrs)

        {:noreply,
         socket
         |> assign(:project, project)
         |> DebuggerSupport.refresh()
         |> maybe_schedule_debugger_auto_fire_refresh()}
    end
  end

  def handle_event("debugger-set-subscription-enabled", params, socket) do
    case socket.assigns.project do
      nil ->
        {:noreply, socket}

      project ->
        attrs = %{
          target: Map.get(params, "target"),
          trigger: Map.get(params, "trigger"),
          enabled: Map.get(params, "enabled")
        }

        project = persist_project_subscription_enabled_setting(project, attrs)
        {:ok, _state} = Ide.Debugger.set_subscription_enabled(Projects.scope_key(project), attrs)

        {:noreply,
         socket
         |> assign(:project, project)
         |> DebuggerSupport.refresh()
         |> maybe_schedule_debugger_auto_fire_refresh()}
    end
  end

  def handle_event("debugger-save-configuration", %{"configuration" => values}, socket)
      when is_map(values) do
    values = normalize_configuration_form_values(values)

    case socket.assigns.project do
      nil ->
        {:noreply, socket}

      project ->
        project = persist_project_debugger_configuration_values(project, values)
        {:ok, _state} = Ide.Debugger.save_configuration(Projects.scope_key(project), values)

        {:noreply,
         socket
         |> assign(:project, project)
         |> assign(:debugger_configuration_draft_values, %{})
         |> DebuggerSupport.refresh()
         |> DebuggerSupport.jump_latest()
         |> put_flash(:info, "Saved companion configuration.")}
    end
  end

  def handle_event("debugger-save-configuration", _params, socket), do: {:noreply, socket}

  def handle_event("debugger-change-configuration", %{"configuration" => values}, socket)
      when is_map(values) do
    {:noreply,
     assign(
       socket,
       :debugger_configuration_draft_values,
       normalize_configuration_form_values(values)
     )}
  end

  def handle_event("debugger-change-configuration", _params, socket), do: {:noreply, socket}

  def handle_event("debugger-reset-configuration", _params, socket) do
    case socket.assigns.project do
      nil ->
        {:noreply, socket}

      project ->
        project = reset_project_debugger_configuration_values(project)
        {:ok, _state} = Ide.Debugger.reload_configuration(Projects.scope_key(project))

        {:noreply,
         socket
         |> assign(:project, project)
         |> assign(:debugger_configuration_draft_values, %{})
         |> DebuggerSupport.refresh()
         |> put_flash(:info, "Reset companion configuration.")}
    end
  end

  def handle_event(
        "debugger-set-watch-profile",
        %{"watch_profile_id" => watch_profile_id},
        socket
      )
      when is_binary(watch_profile_id) do
    case socket.assigns.project do
      nil ->
        {:noreply, socket}

      project ->
        selected_watch_profile_id = normalize_debugger_watch_profile_id(watch_profile_id)
        project = persist_project_debugger_watch_profile(project, selected_watch_profile_id)

        {:ok, _state} =
          Ide.Debugger.set_watch_profile(Projects.scope_key(project), %{
            watch_profile_id: selected_watch_profile_id
          })

        {:noreply,
         socket
         |> assign(:project, project)
         |> DebuggerSupport.refresh()
         |> put_flash(:info, "Debugger watch profile set to #{selected_watch_profile_id}.")}
    end
  end

  def handle_event("debugger-save-simulator-settings", %{"debugger_simulator" => values}, socket)
      when is_map(values) do
    handle_simulator_save_settings(socket, values)
  end

  def handle_event("debugger-save-simulator-settings", %{"simulator" => values}, socket)
      when is_map(values) do
    handle_simulator_save_settings(socket, values)
  end

  def handle_event("debugger-save-simulator-settings", _params, socket), do: {:noreply, socket}

  def handle_event("debugger-tick", _params, socket) do
    case socket.assigns.project do
      nil ->
        {:noreply, socket}

      project ->
        {:ok, _state} = Ide.Debugger.tick(Projects.scope_key(project), %{target: "watch"})

        {:noreply,
         socket
         |> DebuggerSupport.refresh()
         |> DebuggerSupport.jump_latest()
         |> put_flash(:info, "Injected subscription tick.")}
    end
  end

  def handle_event("debugger-auto-tick-start", _params, socket) do
    case socket.assigns.project do
      nil ->
        {:noreply, socket}

      project ->
        {:ok, _state} =
          Ide.Debugger.start_auto_tick(Projects.scope_key(project), %{
            target: "watch",
            interval_ms: 1_000,
            count: 1
          })

        {:noreply,
         socket |> DebuggerSupport.refresh() |> put_flash(:info, "Auto tick started (1000ms).")}
    end
  end

  def handle_event("debugger-auto-tick-stop", _params, socket) do
    case socket.assigns.project do
      nil ->
        {:noreply, socket}

      project ->
        {:ok, _state} = Ide.Debugger.stop_auto_tick(Projects.scope_key(project))
        {:noreply, socket |> DebuggerSupport.refresh() |> put_flash(:info, "Auto tick stopped.")}
    end
  end

  def handle_event("debugger-jump-latest", _params, socket) do
    {:noreply, DebuggerSupport.jump_latest(socket)}
  end

  def handle_event("debugger-step-back", _params, socket) do
    {:noreply, DebuggerSupport.step_back(socket)}
  end

  def handle_event("debugger-step-forward", _params, socket) do
    {:noreply, DebuggerSupport.step_forward(socket)}
  end

  def handle_event("debugger-open-trigger-modal", %{"trigger" => trigger} = params, socket)
      when is_binary(trigger) do
    if debugger_trigger_modal_supported?(socket, params) do
      {:noreply, open_debugger_trigger_modal(socket, params)}
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         "This subscribed event needs a payload shape the debugger form cannot represent."
       )}
    end
  end

  def handle_event("debugger-close-trigger-modal", _params, socket) do
    {:noreply, close_debugger_trigger_modal(socket)}
  end

  def handle_event("debugger-trigger-form-change", %{"debugger_trigger" => params}, socket) do
    merged = merge_debugger_trigger_form(socket, params)

    {:noreply, assign(socket, debugger_trigger_form: to_form(merged, as: :debugger_trigger))}
  end

  def handle_event("debugger-submit-trigger", %{"debugger_trigger" => params}, socket) do
    case socket.assigns.project do
      nil ->
        {:noreply, close_debugger_trigger_modal(socket)}

      project ->
        trigger = Map.get(params, "trigger")

        attrs =
          %{
            trigger: trigger,
            target: Map.get(params, "target"),
            message: debugger_trigger_submit_message(params)
          }
          |> maybe_put_trigger_message_value(params)

        {:ok, _state} = Ide.Debugger.inject_trigger(Projects.scope_key(project), attrs)

        {:noreply,
         socket
         |> close_debugger_trigger_modal()
         |> DebuggerSupport.refresh()
         |> DebuggerSupport.jump_latest()
         |> put_flash(:info, "Injected trigger #{trigger}.")}
    end
  end

  def handle_event("debugger-inject-trigger", %{"trigger" => trigger} = params, socket)
      when is_binary(trigger) do
    case socket.assigns.project do
      nil ->
        {:noreply, socket}

      project ->
        attrs = %{
          trigger: trigger,
          target: Map.get(params, "target"),
          message: Map.get(params, "message"),
          message_value: Map.get(params, "message_value")
        }

        {:ok, _state} = Ide.Debugger.inject_trigger(Projects.scope_key(project), attrs)

        {:noreply,
         socket
         |> DebuggerSupport.refresh()
         |> DebuggerSupport.jump_latest()
         |> put_flash(:info, "Injected trigger #{trigger}.")}
    end
  end

  def handle_event("debugger-sim-compass", _params, socket) do
    inject_simulator_watch_trigger(socket, "compass", "Compass heading sent.")
  end

  def handle_event("debugger-sim-focus", _params, socket) do
    inject_simulator_watch_trigger(socket, "app_focus", "App focus change sent.")
  end

  def handle_event("debugger-sim-dictation", _params, socket) do
    with {:ok, socket} <-
           inject_simulator_watch_trigger(socket, "dictation_status", nil, flash: false),
         {:ok, socket} <-
           inject_simulator_watch_trigger(
             socket,
             "dictation_result",
             "Dictation simulation sent."
           ) do
      {:noreply, socket}
    else
      {:noreply, socket} -> {:noreply, socket}
    end
  end

  def handle_event("debugger-sim-vibes", _params, socket) do
    case socket.assigns.project do
      nil ->
        {:noreply, socket}

      project ->
        settings =
          SimulatorSettings.values_for(project, socket.assigns[:debugger_state])

        segments = Map.get(settings, "vibe_pattern_ms", [])

        if is_list(segments) and segments != [] do
          {:noreply, put_flash(socket, :info, "Vibration pattern queued in simulator settings.")}
        else
          {:noreply,
           put_flash(
             socket,
             :warning,
             "Configure a vibration pattern in simulator settings first."
           )}
        end
    end
  end

  def handle_event("debugger-select-debugger-event", %{"seq" => seq}, socket) do
    {:noreply, DebuggerSupport.set_debugger_cursor_seq(socket, seq)}
  end

  def handle_event("debugger-hover-rendered-node", %{"path" => path, "scope" => scope}, socket)
      when is_binary(path) and is_binary(scope) do
    {:noreply,
     socket
     |> assign(:debugger_hovered_rendered_scope, scope)
     |> assign(:debugger_hovered_rendered_path, path)}
  end

  def handle_event("debugger-clear-rendered-node-hover", _params, socket) do
    {:noreply,
     socket
     |> assign(:debugger_hovered_rendered_scope, nil)
     |> assign(:debugger_hovered_rendered_path, nil)}
  end

  def handle_event("debugger-keydown", %{"key" => "j"}, socket) do
    {:noreply, DebuggerSupport.step_back(socket)}
  end

  def handle_event("debugger-keydown", %{"key" => "k"}, socket) do
    {:noreply, DebuggerSupport.step_forward(socket)}
  end

  defp handle_simulator_save_settings(socket, values) when is_map(values) do
    case socket.assigns.project do
      nil ->
        {:noreply, socket}

      project ->
        existing = SimulatorSettings.raw_settings_for(project, socket.assigns[:debugger_state])
        simulator_settings = SimulatorSettings.save_from_form(existing, values)

        focus_changed? =
          normalize_boolean_setting(Map.get(existing, "app_in_focus", true)) !=
            normalize_boolean_setting(Map.get(simulator_settings, "app_in_focus"))

        project = persist_project_debugger_simulator_settings(project, simulator_settings)

        {:ok, _state} =
          Ide.Debugger.set_simulator_settings(Projects.scope_key(project), simulator_settings)

        socket =
          socket
          |> assign(:project, project)
          |> push_event("simulator_settings_applied", simulator_settings)
          |> maybe_sync_external_emulator_settings(simulator_settings)

        socket =
          if focus_changed? do
            case inject_simulator_watch_trigger(project, "app_focus") do
              {:ok, _state} -> socket |> DebuggerSupport.refresh()
              {:error, _} -> socket
            end
          else
            socket
          end

        {:noreply, socket |> DebuggerSupport.refresh()}
    end
  end

  defp normalize_boolean_setting(value) when value in [true, "true", "1", 1], do: true
  defp normalize_boolean_setting(_value), do: false

  @spec inject_simulator_watch_trigger(socket(), String.t(), String.t() | nil, keyword()) ::
          {:ok, socket()} | lv_noreply()
  defp inject_simulator_watch_trigger(socket, kind, flash_message, opts \\ []) do
    flash? = Keyword.get(opts, :flash, true)

    case socket.assigns.project do
      nil ->
        {:noreply, socket}

      project ->
        case inject_simulator_watch_trigger(project, kind) do
          {:ok, _state} ->
            socket =
              socket
              |> DebuggerSupport.refresh()
              |> DebuggerSupport.jump_latest()
              |> then(fn s ->
                if flash? and is_binary(flash_message),
                  do: put_flash(s, :info, flash_message),
                  else: s
              end)

            {:ok, socket}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not inject #{kind} simulator trigger.")}
        end
    end
  end

  @spec inject_simulator_watch_trigger(Project.t(), String.t()) ::
          {:ok, Ide.Debugger.Types.RuntimeState.t()} | {:error, :trigger_not_found}
  defp inject_simulator_watch_trigger(%Project{} = project, kind) when is_binary(kind) do
    slug = Projects.scope_key(project)

    with {:ok, rows} <- Ide.Debugger.available_triggers(slug, %{"target" => "watch"}),
         row <- find_simulator_trigger_row(rows, kind),
         {:ok, attrs} <- simulator_trigger_attrs(row, kind) do
      Ide.Debugger.inject_trigger(slug, attrs)
    else
      _ -> {:error, :trigger_not_found}
    end
  end

  defp find_simulator_trigger_row(rows, kind) when is_list(rows) do
    patterns =
      case kind do
        "compass" -> ["compass"]
        "app_focus" -> ["app_focus", "appfocus"]
        "unobstructed_area" -> ["unobstructed", "timeline_peek"]
        "dictation_status" -> ["dictation_status", "dictationstatus"]
        "dictation_result" -> ["dictation_result", "dictationresult"]
        _ -> [kind]
      end

    Enum.find(rows, fn row ->
      trigger =
        row
        |> Map.get(:trigger, Map.get(row, "trigger", ""))
        |> to_string()
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9]+/, "")

      Enum.any?(patterns, &String.contains?(trigger, &1))
    end)
  end

  defp simulator_trigger_attrs(nil, kind) do
    trigger =
      case kind do
        "compass" -> "on_compass_change"
        "app_focus" -> "on_app_focus_change"
        "unobstructed_area" -> "on_unobstructed_will_change"
        "dictation_status" -> "on_dictation_status"
        "dictation_result" -> "on_dictation_result"
        other -> other
      end

    {:ok, %{trigger: trigger, target: "watch"}}
  end

  defp simulator_trigger_attrs(row, _kind) do
    {:ok,
     %{
       trigger: Map.get(row, :trigger) || Map.get(row, "trigger"),
       target: Map.get(row, :target) || Map.get(row, "target") || "watch",
       message: Map.get(row, :message) || Map.get(row, "message")
     }}
  end

  def handle_async(:debugger_bootstrap, {:ok, {:ok, result}}, socket) do
    {:noreply, complete_debugger_bootstrap(socket, result)}
  end

  def handle_async(:debugger_bootstrap, {:ok, {:error, message}}, socket)
      when is_binary(message) do
    {:noreply,
     socket
     |> clear_debugger_bootstrap_busy()
     |> put_flash(:error, message)}
  end

  def handle_async(:debugger_bootstrap, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> clear_debugger_bootstrap_busy()
     |> put_flash(:error, "Debugger start failed: #{inspect(reason)}")}
  end

  @spec handle_info(Types.info_message() | Types.liveview_system_message(), socket()) ::
          lv_noreply()
  def handle_info({:companion_debugger_bootstrapped, scope_key, result}, socket) do
    project = socket.assigns[:project]

    cond do
      not match?(%Project{}, project) ->
        {:noreply, socket}

      Projects.scope_key(project) != scope_key ->
        {:noreply, socket}

      true ->
        socket =
          case result do
            {:error, message} when is_binary(message) ->
              put_flash(socket, :error, message)

            _ ->
              socket
          end

        apply_project_auto_fire_settings(project)

        {:noreply,
         socket
         |> assign(:debugger_companion_bootstrap_status, :idle)
         |> assign(:debugger_companion_bootstrap_progress, nil)
         |> schedule_debugger_runtime_refresh()
         |> maybe_schedule_debugger_auto_fire_refresh()}
    end
  end

  def handle_info({:debugger_bootstrap_progress, token, message}, socket) do
    if socket.assigns[:debugger_bootstrap_token] == token do
      {:noreply, assign(socket, :debugger_bootstrap_progress, message)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:debugger_companion_bootstrap_progress, message}, socket)
      when is_binary(message) do
    {:noreply,
     socket
     |> assign(:debugger_companion_bootstrap_progress, message)
     |> schedule_debugger_runtime_refresh()}
  end

  def handle_info(:debugger_runtime_updated, socket) do
    {:noreply, schedule_debugger_runtime_refresh(socket)}
  end

  def handle_info({:debugger_runtime_refresh, seq}, socket) when is_integer(seq) do
    if socket.assigns[:debugger_runtime_refresh_seq] == seq do
      socket = DebuggerSupport.refresh_following_debugger_latest(socket)

      socket =
        if socket.assigns[:debugger_companion_bootstrap_status] == :running and
             DebuggerBootstrapFlow.companion_bootstrapped?(socket.assigns[:debugger_state]) do
          socket
          |> assign(:debugger_companion_bootstrap_status, :idle)
          |> assign(:debugger_companion_bootstrap_progress, nil)
        else
          socket
        end

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:debugger_auto_fire_refresh, project_slug}, socket) do
    socket = assign(socket, :debugger_auto_fire_refresh_scheduled, false)
    project = socket.assigns[:project]

    cond do
      not match?(%Project{}, project) ->
        {:noreply, socket}

      project.slug != project_slug ->
        {:noreply, socket}

      true ->
        socket =
          socket
          |> DebuggerSupport.refresh_following_debugger_latest()
          |> maybe_schedule_debugger_auto_fire_refresh()

        {:noreply, socket}
    end
  end

  @spec debugger_session_active?(socket()) :: boolean()
  def debugger_session_active?(socket) do
    debugger_state_running?(socket.assigns[:debugger_state])
  end

  @spec debugger_state_running?(map() | nil) :: boolean()
  defp debugger_state_running?(%{running: true}), do: true
  defp debugger_state_running?(_), do: false

  @spec begin_debugger_bootstrap(socket(), Project.t()) :: socket()
  def begin_debugger_bootstrap(socket, project) do
    token = System.unique_integer([:positive])
    lv = self()
    bootstrap_tab = debugger_bootstrap_tab_snapshot(socket)
    watch_profile_id = project_debugger_watch_profile_id(project)

    socket =
      socket
      |> assign(:debugger_bootstrap_status, :running)
      |> assign(:debugger_bootstrap_progress, "Starting debugger...")
      |> assign(:debugger_bootstrap_token, token)

    run_opts = [
      progress: fn msg -> send(lv, {:debugger_bootstrap_progress, token, msg}) end,
      bootstrap_tab: bootstrap_tab,
      watch_profile_id: watch_profile_id
    ]

    if debugger_sync_bootstrap?() do
      case DebuggerBootstrapFlow.run(project, run_opts) do
        {:ok, result} ->
          complete_debugger_bootstrap(socket, result)

        {:error, message} ->
          socket |> clear_debugger_bootstrap_busy() |> put_flash(:error, message)
      end
    else
      start_async(socket, :debugger_bootstrap, fn ->
        DebuggerBootstrapFlow.run(project, run_opts)
      end)
    end
  end

  @spec complete_debugger_bootstrap(socket(), DebuggerBootstrapFlow.result()) :: socket()
  def complete_debugger_bootstrap(socket, result) do
    project = socket.assigns.project

    socket =
      socket
      |> BuildFlow.apply_warm_compile_results(result.compile_results, result.primary)
      |> DebuggerSupport.refresh()

    socket =
      if result.companion_async? do
        apply_project_auto_fire_settings(project)
        schedule_companion_debugger_bootstrap(project, socket)

        socket
        |> clear_debugger_bootstrap_busy()
        |> assign(:debugger_companion_bootstrap_status, :running)
        |> assign(:debugger_companion_bootstrap_progress, "Loading companion app...")
        |> put_flash(:info, result.message)
        |> DebuggerSupport.refresh()
        |> maybe_schedule_debugger_auto_fire_refresh()
      else
        apply_project_auto_fire_settings(project)

        socket
        |> DebuggerSupport.refresh()
        |> maybe_schedule_debugger_auto_fire_refresh()
        |> clear_debugger_bootstrap_busy()
        |> put_flash(:info, result.message)
      end

    if debugger_session_active?(socket) do
      BuildFlow.schedule_compiler_check(socket)
    else
      socket
    end
  end

  @spec clear_debugger_bootstrap_busy(socket()) :: socket()
  def clear_debugger_bootstrap_busy(socket) do
    socket
    |> assign(:debugger_bootstrap_status, :idle)
    |> assign(:debugger_bootstrap_progress, nil)
    |> assign(:debugger_bootstrap_token, nil)
  end

  @spec debugger_bootstrap_tab_snapshot(socket()) :: DebuggerBootstrapFlow.bootstrap_tab()
  defp debugger_bootstrap_tab_snapshot(socket) do
    case EditorSupport.active_tab(socket) do
      %{rel_path: rel_path, content: content, source_root: source_root}
      when is_binary(rel_path) and is_binary(content) and is_binary(source_root) ->
        %{rel_path: rel_path, content: content, source_root: source_root}

      _ ->
        nil
    end
  end

  @spec debugger_sync_bootstrap?() :: boolean()
  defp debugger_sync_bootstrap? do
    Application.get_env(:ide, :debugger_sync_bootstrap, false)
  end

  @spec schedule_companion_debugger_bootstrap(Projects.Project.t(), socket()) :: :ok
  defp schedule_companion_debugger_bootstrap(project, _socket) do
    if DebuggerBootstrapFlow.companion_bootstrap_async?() do
      scope_key = Projects.scope_key(project)
      parent = self()

      Task.start(fn ->
        result =
          try do
            DebuggerBootstrapFlow.run_companion_bootstrap(project,
              progress: fn msg ->
                send(parent, {:debugger_companion_bootstrap_progress, msg})
              end
            )
          rescue
            exception ->
              {:error, Exception.message(exception)}
          end

        send(parent, :debugger_runtime_updated)
        send(parent, {:companion_debugger_bootstrapped, scope_key, result})
      end)

      :ok
    else
      _ = DebuggerBootstrapFlow.run_companion_bootstrap(project)
      :ok
    end
  end

  @spec maybe_ensure_companion_bootstrapped(socket()) :: socket()
  def maybe_ensure_companion_bootstrapped(socket) do
    project = socket.assigns[:project]
    state = socket.assigns[:debugger_state]

    cond do
      not Phoenix.LiveView.connected?(socket) ->
        socket

      socket.assigns[:pane] != :debugger ->
        socket

      not match?(%Project{}, project) ->
        socket

      not Projects.companion_app_present?(project) ->
        socket

      not debugger_session_active?(socket) ->
        socket

      socket.assigns[:debugger_companion_bootstrap_status] == :running ->
        socket

      DebuggerBootstrapFlow.companion_bootstrapped?(state) ->
        socket

      DebuggerBootstrapFlow.companion_bootstrap_incomplete?(state) ->
        schedule_companion_debugger_bootstrap(project, socket)

        socket
        |> assign(:debugger_companion_bootstrap_status, :running)
        |> assign(:debugger_companion_bootstrap_progress, "Loading companion app...")

      true ->
        schedule_companion_debugger_bootstrap(project, socket)

        socket
        |> assign(:debugger_companion_bootstrap_status, :running)
        |> assign(:debugger_companion_bootstrap_progress, "Loading companion app...")
    end
  end

  @spec schedule_debugger_runtime_refresh(socket()) :: socket()
  def schedule_debugger_runtime_refresh(socket) do
    ms = Application.get_env(:ide, :debugger_runtime_refresh_debounce_ms, 100)
    seq = (socket.assigns[:debugger_runtime_refresh_seq] || 0) + 1

    if ref = socket.assigns[:debugger_runtime_refresh_ref] do
      Process.cancel_timer(ref)
    end

    ref = Process.send_after(self(), {:debugger_runtime_refresh, seq}, ms)

    socket
    |> assign(:debugger_runtime_refresh_ref, ref)
    |> assign(:debugger_runtime_refresh_seq, seq)
  end

  @spec persist_project_debugger_timeline_mode(Project.t(), String.t()) :: Project.t()
  defp persist_project_debugger_timeline_mode(%Project{} = project, mode)
       when mode in ["watch", "companion", "mixed", "separate"] do
    mode =
      normalize_project_debugger_timeline_mode(mode, Projects.companion_app_present?(project))

    settings = project.debugger_settings || %{}
    updated_settings = Map.put(settings, "timeline_mode", mode)

    case Projects.update_project(project, %{"debugger_settings" => updated_settings}) do
      {:ok, updated} -> updated
      {:error, _} -> project
    end
  end

  defp persist_project_debugger_timeline_mode(project, _mode), do: project

  @spec persist_project_debugger_watch_profile(Project.t(), String.t()) :: Project.t()
  defp persist_project_debugger_watch_profile(%Project{} = project, watch_profile_id)
       when is_binary(watch_profile_id) do
    profile_id = normalize_debugger_watch_profile_id(watch_profile_id)
    settings = project.debugger_settings || %{}
    updated_settings = Map.put(settings, "watch_profile_id", profile_id)

    case Projects.update_project(project, %{"debugger_settings" => updated_settings}) do
      {:ok, updated} -> updated
      {:error, _} -> project
    end
  end

  defp persist_project_debugger_watch_profile(project, _watch_profile_id), do: project

  @spec persist_project_debugger_simulator_settings(Project.t(), map()) :: Project.t()
  defp persist_project_debugger_simulator_settings(%Project{} = project, settings)
       when is_map(settings) do
    current_settings = project.debugger_settings || %{}

    updated_settings =
      Map.put(current_settings, "simulator", settings)

    case Projects.update_project(project, %{"debugger_settings" => updated_settings}) do
      {:ok, updated} -> updated
      {:error, _} -> project
    end
  end

  defp persist_project_debugger_simulator_settings(project, _settings), do: project

  defp maybe_sync_external_emulator_settings(socket, settings) when is_map(settings) do
    if socket.assigns[:emulator_mode] == "external" and not external_emulator_blocked?(socket) do
      project = socket.assigns.project
      emulator_target = socket.assigns.selected_emulator_target

      controls = QemuControl.external_cli_commands(settings)

      start_async(socket, :external_emulator_control, fn ->
        Enum.each(controls, fn params ->
          PebbleToolchain.run_emulator_control(project.slug, emulator_target, params)
        end)

        {:ok, :synced}
      end)
    else
      socket
    end
  end

  @spec persist_project_debugger_configuration_values(Project.t(), map()) :: Project.t()
  defp persist_project_debugger_configuration_values(%Project{} = project, values)
       when is_map(values) do
    settings = project.debugger_settings || %{}
    updated_settings = Map.put(settings, "configuration_values", Map.new(values))

    case Projects.update_project(project, %{"debugger_settings" => updated_settings}) do
      {:ok, updated} -> updated
      {:error, _} -> project
    end
  end

  defp persist_project_debugger_configuration_values(project, _values), do: project

  @spec normalize_configuration_form_values(map()) :: map()
  defp normalize_configuration_form_values(values) when is_map(values) do
    Map.new(values, fn
      {key, list} when is_list(list) -> {key, normalize_configuration_form_list_value(list)}
      entry -> entry
    end)
  end

  @spec normalize_configuration_form_list_value([wire_input()]) :: wire_input()
  defp normalize_configuration_form_list_value(values) when is_list(values) do
    if Enum.all?(values, &configuration_boolean_form_value?/1) do
      Enum.any?(values, &configuration_truthy_form_value?/1)
    else
      List.last(values)
    end
  end

  defp configuration_boolean_form_value?(value)
       when value in [true, false, "true", "false", "True", "False", "on", "off", "1", "0", 1, 0],
       do: true

  defp configuration_boolean_form_value?(_value), do: false

  defp configuration_truthy_form_value?(value) when value in [true, "true", "True", "on", "1", 1],
    do: true

  defp configuration_truthy_form_value?(_value), do: false

  @spec reset_project_debugger_configuration_values(Project.t()) :: Project.t()
  defp reset_project_debugger_configuration_values(%Project{} = project) do
    settings = project.debugger_settings || %{}
    updated_settings = Map.delete(settings, "configuration_values")

    case Projects.update_project(project, %{"debugger_settings" => updated_settings}) do
      {:ok, updated} -> updated
      {:error, _} -> project
    end
  end

  defp reset_project_debugger_configuration_values(project), do: project

  @spec project_debugger_timeline_mode(Project.t()) :: String.t()
  def project_debugger_timeline_mode(%Project{} = project) do
    settings = project.debugger_settings || %{}
    companion_app_present? = Projects.companion_app_present?(project)

    case Map.get(settings, "timeline_mode") do
      mode when mode in ["watch", "companion", "mixed", "separate"] ->
        normalize_project_debugger_timeline_mode(mode, companion_app_present?)

      _ ->
        "mixed"
    end
  end

  @spec normalize_project_debugger_timeline_mode(wire_input(), boolean()) :: String.t()
  defp normalize_project_debugger_timeline_mode(_mode, false), do: "watch"

  defp normalize_project_debugger_timeline_mode(mode, true)
       when mode in ["watch", "companion", "mixed", "separate"],
       do: mode

  defp normalize_project_debugger_timeline_mode(_mode, true), do: "mixed"

  @spec project_debugger_watch_profile_id(Project.t()) :: String.t()
  defp project_debugger_watch_profile_id(%Project{} = project) do
    settings = project.debugger_settings || %{}
    normalize_debugger_watch_profile_id(Map.get(settings, "watch_profile_id"))
  end

  @spec normalize_debugger_watch_profile_id(wire_input()) :: String.t()
  def normalize_debugger_watch_profile_id(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()

    if normalized in debugger_watch_profile_ids(),
      do: normalized,
      else: default_debugger_watch_profile_id()
  end

  def normalize_debugger_watch_profile_id(_), do: default_debugger_watch_profile_id()

  @spec debugger_watch_profile_ids() :: [String.t()]
  defp debugger_watch_profile_ids do
    Ide.Debugger.watch_profiles()
    |> Enum.map(&Map.get(&1, "id"))
    |> Enum.filter(&is_binary/1)
  end

  @spec open_debugger_trigger_modal(socket(), map()) :: socket()
  defp open_debugger_trigger_modal(socket, params) when is_map(params) do
    trigger = Map.get(params, "trigger") || ""
    target = Map.get(params, "target") || "watch"
    message = Map.get(params, "message") || ""
    debugger_state = socket.assigns[:debugger_state]

    trigger_display =
      Map.get(params, "trigger_display") ||
        Ide.Debugger.subscription_trigger_display_for(debugger_state, trigger, target)

    form_data =
      case Ide.Debugger.CompanionSubscriptionTrigger.form_data(debugger_state, trigger, message) do
        %{} = companion_form ->
          companion_form
          |> Map.merge(%{
            "target" => target,
            "trigger" => trigger,
            "trigger_display" => trigger_display
          })

        _ ->
          default_debugger_trigger_form(trigger, target, message, trigger_display)
      end

    assign(socket,
      debugger_trigger_modal_open: true,
      debugger_trigger_form: to_form(form_data, as: :debugger_trigger)
    )
  end

  @spec debugger_trigger_modal_supported?(socket(), map()) :: boolean()
  defp debugger_trigger_modal_supported?(socket, params) when is_map(params) do
    state = socket.assigns[:debugger_state]

    row = %{
      trigger: Map.get(params, "trigger") || Map.get(params, :trigger),
      target: Map.get(params, "target") || Map.get(params, :target),
      message: Map.get(params, "message") || Map.get(params, :message)
    }

    Ide.Debugger.subscription_trigger_injection_modal_supported?(state, row)
  end

  @spec close_debugger_trigger_modal(socket()) :: socket()
  defp close_debugger_trigger_modal(socket) do
    assign(socket,
      debugger_trigger_modal_open: false,
      debugger_trigger_form: to_form(%{}, as: :debugger_trigger)
    )
  end

  @spec merge_debugger_trigger_form(socket(), map()) :: map()
  defp merge_debugger_trigger_form(socket, params) when is_map(params) do
    previous =
      case socket.assigns[:debugger_trigger_form] do
        %Phoenix.HTML.Form{source: source} when is_map(source) -> source
        _ -> %{}
      end

    previous
    |> Map.merge(params)
    |> sync_debugger_trigger_companion_fields(params)
    |> ensure_debugger_trigger_error_message()
  end

  @spec sync_debugger_trigger_companion_fields(map(), map()) :: map()
  defp sync_debugger_trigger_companion_fields(%{"companion_fields" => fields} = merged, params)
       when is_list(fields) and is_map(params) do
    updated_fields =
      Enum.map(fields, fn field ->
        key = field["key"] || field[:key]

        case Map.get(params, "companion_field_#{key}") do
          nil ->
            field

          value ->
            Map.put(field, "value", to_string(value))
        end
      end)

    Map.put(merged, "companion_fields", updated_fields)
  end

  defp sync_debugger_trigger_companion_fields(merged, _params), do: merged

  @spec ensure_debugger_trigger_error_message(map()) :: map()
  defp ensure_debugger_trigger_error_message(%{"result" => "Err"} = params) do
    case Map.get(params, "error_message") do
      msg when is_binary(msg) ->
        if String.trim(msg) != "",
          do: params,
          else: Map.put(params, "error_message", "Unavailable")

      _ ->
        Map.put(params, "error_message", "Unavailable")
    end
  end

  defp ensure_debugger_trigger_error_message(params), do: params

  @spec default_debugger_trigger_form(String.t(), String.t(), String.t(), String.t()) :: map()
  defp default_debugger_trigger_form(trigger, target, message, trigger_display) do
    constructor =
      case message do
        value when is_binary(value) and value != "" -> value
        _ -> default_debugger_message_for_trigger(trigger)
      end

    display =
      case trigger_display do
        value when is_binary(value) and value != "" -> value
        _ -> Ide.Debugger.subscription_trigger_display_for(%{}, trigger, target)
      end

    normalized_trigger = trigger |> to_string() |> String.downcase()
    now = NaiveDateTime.local_now()

    {payload_kind, payload, final_message} =
      cond do
        contains_any?(normalized_trigger, ["on_minute_change", "onminutechange"]) ->
          {"integer", Integer.to_string(now.minute),
           append_single_payload(constructor, now.minute)}

        contains_any?(normalized_trigger, ["on_hour_change", "onhourchange"]) ->
          {"integer", Integer.to_string(now.hour), append_single_payload(constructor, now.hour)}

        contains_any?(normalized_trigger, ["on_battery_change", "onbatterychange"]) ->
          {"integer", "88", append_single_payload(constructor, 88)}

        contains_any?(normalized_trigger, ["on_connection_change", "onconnectionchange"]) ->
          {"boolean", "True", append_single_payload(constructor, "True")}

        contains_any?(normalized_trigger, ["on_second_change", "onsecondchange"]) ->
          {"integer", Integer.to_string(now.second),
           append_single_payload(constructor, now.second)}

        contains_any?(normalized_trigger, ["on_day_change", "ondaychange"]) ->
          {"integer", Integer.to_string(now.day), append_single_payload(constructor, now.day)}

        contains_any?(normalized_trigger, ["on_month_change", "onmonthchange"]) ->
          {"integer", Integer.to_string(now.month), append_single_payload(constructor, now.month)}

        contains_any?(normalized_trigger, ["on_year_change", "onyearchange"]) ->
          {"integer", Integer.to_string(now.year), append_single_payload(constructor, now.year)}

        true ->
          {"message", "", constructor}
      end

    %{
      "target" => target,
      "trigger" => trigger,
      "trigger_display" => display,
      "message_constructor" => constructor,
      "payload_kind" => payload_kind,
      "payload" => payload,
      "message" => final_message
    }
  end

  defp default_debugger_message_for_trigger(trigger) do
    trigger
    |> to_string()
    |> String.downcase()
    |> then(fn normalized ->
      if contains_any?(normalized, ["tick", "time", "clock"]), do: "Tick", else: ""
    end)
  end

  defp append_single_payload(message, value) when is_binary(message) and is_integer(value) do
    if String.contains?(String.trim(message), " ") do
      message
    else
      "#{message} #{value}"
    end
  end

  defp append_single_payload(message, value) when is_binary(message) and is_binary(value) do
    if String.contains?(String.trim(message), " ") do
      message
    else
      "#{message} #{value}"
    end
  end

  @spec debugger_trigger_submit_message(map()) :: String.t()
  defp debugger_trigger_submit_message(params) when is_map(params) do
    case Map.get(params, "payload_kind") do
      "companion_bridge" ->
        Map.get(params, "message_constructor") || Map.get(params, "message") || "Msg"

      "integer" ->
        constructor =
          Map.get(params, "message_constructor") || Map.get(params, "message") || "Tick"

        payload = Map.get(params, "payload") || ""
        "#{String.trim(constructor)} #{String.trim(payload)}" |> String.trim()

      "boolean" ->
        constructor =
          Map.get(params, "message_constructor") || Map.get(params, "message") || "Tick"

        payload = Map.get(params, "payload") || "True"
        "#{String.trim(constructor)} #{String.trim(payload)}" |> String.trim()

      "none" ->
        Map.get(params, "message_constructor") || Map.get(params, "message") || "Tick"

      _ ->
        Map.get(params, "message") || Map.get(params, "message_constructor") || "Tick"
    end
  end

  @spec maybe_put_trigger_message_value(map(), map()) :: map()
  defp maybe_put_trigger_message_value(attrs, %{"payload_kind" => "companion_bridge"} = params) do
    case Ide.Debugger.CompanionSubscriptionTrigger.message_value(params) do
      %{} = message_value -> Map.put(attrs, :message_value, message_value)
      _ -> attrs
    end
  end

  defp maybe_put_trigger_message_value(attrs, _params), do: attrs

  defp contains_any?(text, needles) when is_binary(text) and is_list(needles) do
    Enum.any?(needles, &String.contains?(text, &1))
  end

  @spec default_debugger_watch_profile_id() :: String.t()
  defp default_debugger_watch_profile_id do
    debugger_watch_profile_ids()
    |> List.first()
    |> case do
      id when is_binary(id) -> id
      _ -> "basalt"
    end
  end

  @spec persist_project_auto_fire_setting(Project.t(), map()) :: Project.t()
  defp persist_project_auto_fire_setting(%Project{} = project, attrs) when is_map(attrs) do
    target = debugger_auto_fire_target(Map.get(attrs, :target) || Map.get(attrs, "target"))
    trigger = Map.get(attrs, :trigger) || Map.get(attrs, "trigger")
    enabled? = debugger_checkbox_enabled?(Map.get(attrs, :enabled) || Map.get(attrs, "enabled"))
    settings = project.debugger_settings || %{}

    updated_settings =
      if is_binary(trigger) and String.trim(trigger) != "" do
        subscriptions =
          settings
          |> Map.get("auto_fire_subscriptions", [])
          |> update_project_auto_fire_subscriptions(target, trigger, enabled?)

        auto_fire = Map.get(settings, "auto_fire", %{})

        settings
        |> Map.put("auto_fire", Map.put(auto_fire, target, false))
        |> Map.put("auto_fire_subscriptions", subscriptions)
      else
        auto_fire = Map.get(settings, "auto_fire", %{})
        Map.put(settings, "auto_fire", Map.put(auto_fire, target, enabled?))
      end

    case Projects.update_project(project, %{"debugger_settings" => updated_settings}) do
      {:ok, updated} -> updated
      {:error, _} -> project
    end
  end

  defp persist_project_auto_fire_setting(project, _attrs), do: project

  @spec persist_project_subscription_enabled_setting(Project.t(), map()) :: Project.t()
  defp persist_project_subscription_enabled_setting(%Project{} = project, attrs)
       when is_map(attrs) do
    target = debugger_auto_fire_target(Map.get(attrs, :target) || Map.get(attrs, "target"))
    trigger = Map.get(attrs, :trigger) || Map.get(attrs, "trigger")
    enabled? = debugger_checkbox_enabled?(Map.get(attrs, :enabled) || Map.get(attrs, "enabled"))
    settings = project.debugger_settings || %{}

    disabled_subscriptions =
      settings
      |> Map.get("disabled_subscriptions", [])
      |> update_project_disabled_subscriptions(target, trigger, enabled?)

    updated_settings = Map.put(settings, "disabled_subscriptions", disabled_subscriptions)

    case Projects.update_project(project, %{"debugger_settings" => updated_settings}) do
      {:ok, updated} -> updated
      {:error, _} -> project
    end
  end

  defp persist_project_subscription_enabled_setting(project, _attrs), do: project

  @spec apply_project_auto_fire_settings(Project.t()) :: :ok
  defp apply_project_auto_fire_settings(%Project{} = project) do
    settings = project.debugger_settings || %{}

    for %{"target" => target, "trigger" => trigger} <-
          Map.get(settings, "disabled_subscriptions", []),
        auto_fire_trigger_available?(Projects.scope_key(project), target, trigger) do
      {:ok, _state} =
        Ide.Debugger.set_subscription_enabled(Projects.scope_key(project), %{
          target: target,
          trigger: trigger,
          enabled: false
        })
    end

    for %{"target" => target, "trigger" => trigger} <-
          Map.get(settings, "auto_fire_subscriptions", []),
        auto_fire_trigger_available?(Projects.scope_key(project), target, trigger) do
      {:ok, _state} =
        Ide.Debugger.set_auto_fire(Projects.scope_key(project), %{
          target: target,
          trigger: trigger,
          enabled: true
        })
    end

    if Map.get(settings, "auto_fire_subscriptions", []) == [] do
      for target <- ["watch", "protocol"],
          debugger_auto_fire_enabled?(project, target),
          auto_fire_available?(Projects.scope_key(project), target) do
        {:ok, _state} =
          Ide.Debugger.set_auto_fire(Projects.scope_key(project), %{
            target: target,
            enabled: true
          })
      end
    end

    :ok
  end

  @spec auto_fire_available?(String.t(), String.t()) :: boolean()
  defp auto_fire_available?(project_slug, target)
       when is_binary(project_slug) and target in ["watch", "protocol"] do
    {:ok, rows} = Ide.Debugger.available_triggers(project_slug, %{"target" => target})

    Enum.any?(rows, fn row ->
      source = Map.get(row, :source) || Map.get(row, "source")

      is_binary(Map.get(row, :trigger) || Map.get(row, "trigger")) and
        source == "subscription"
    end)
  end

  defp auto_fire_available?(_project_slug, _target), do: false

  defp auto_fire_trigger_available?(project_slug, target, trigger)
       when is_binary(project_slug) and target in ["watch", "protocol"] and is_binary(trigger) do
    {:ok, rows} = Ide.Debugger.available_triggers(project_slug, %{"target" => target})

    Enum.any?(rows, fn row ->
      source = Map.get(row, :source) || Map.get(row, "source")
      row_trigger = Map.get(row, :trigger) || Map.get(row, "trigger")
      source == "subscription" and row_trigger == trigger
    end)
  end

  defp auto_fire_trigger_available?(_project_slug, _target, _trigger), do: false

  defp update_project_auto_fire_subscriptions(subscriptions, target, trigger, enabled?) do
    trigger = String.trim(to_string(trigger))

    subscriptions =
      subscriptions
      |> List.wrap()
      |> Enum.filter(&is_map/1)
      |> Enum.reject(fn row ->
        Map.get(row, "target") == target and Map.get(row, "trigger") == trigger
      end)

    if enabled? do
      [%{"target" => target, "trigger" => trigger} | subscriptions]
    else
      subscriptions
    end
    |> Enum.uniq_by(&{Map.get(&1, "target"), Map.get(&1, "trigger")})
  end

  defp update_project_disabled_subscriptions(subscriptions, target, trigger, enabled?)
       when is_binary(trigger) and trigger != "" do
    trigger = String.trim(trigger)

    subscriptions =
      subscriptions
      |> List.wrap()
      |> Enum.filter(&is_map/1)
      |> Enum.reject(fn row ->
        Map.get(row, "target") == target and Map.get(row, "trigger") == trigger
      end)

    if enabled? do
      subscriptions
    else
      [%{"target" => target, "trigger" => trigger} | subscriptions]
    end
    |> Enum.uniq_by(&{Map.get(&1, "target"), Map.get(&1, "trigger")})
  end

  defp update_project_disabled_subscriptions(subscriptions, _target, _trigger, _enabled?),
    do: List.wrap(subscriptions) |> Enum.filter(&is_map/1)

  @spec maybe_schedule_debugger_auto_fire_refresh(socket()) :: socket()
  def maybe_schedule_debugger_auto_fire_refresh(socket) do
    project = socket.assigns[:project]

    if connected?(socket) and match?(%Project{}, project) and
         debugger_auto_fire_refresh_active?(socket) and
         socket.assigns[:debugger_auto_fire_refresh_scheduled] != true do
      Process.send_after(
        self(),
        {:debugger_auto_fire_refresh, project.slug},
        debugger_auto_fire_refresh_interval_ms(socket)
      )

      assign(socket, :debugger_auto_fire_refresh_scheduled, true)
    else
      socket
    end
  end

  @spec debugger_auto_fire_refresh_active?(socket()) :: boolean()
  defp debugger_auto_fire_refresh_active?(socket) do
    auto_tick =
      socket.assigns[:debugger_state]
      |> case do
        %{auto_tick: auto_tick} when is_map(auto_tick) -> auto_tick
        %{"auto_tick" => auto_tick} when is_map(auto_tick) -> auto_tick
        _ -> %{}
      end

    (Map.get(auto_tick, :enabled) == true or Map.get(auto_tick, "enabled") == true) and
      auto_tick
      |> Map.get(:targets, Map.get(auto_tick, "targets", []))
      |> List.wrap()
      |> Enum.any?()
  end

  @spec debugger_auto_fire_refresh_interval_ms(socket()) :: pos_integer()
  defp debugger_auto_fire_refresh_interval_ms(socket) do
    auto_tick =
      socket.assigns[:debugger_state]
      |> case do
        %{auto_tick: auto_tick} when is_map(auto_tick) -> auto_tick
        %{"auto_tick" => auto_tick} when is_map(auto_tick) -> auto_tick
        _ -> %{}
      end

    auto_tick
    |> Map.get(
      :interval_ms,
      Map.get(auto_tick, "interval_ms", @debugger_auto_fire_refresh_interval_ms)
    )
    |> case do
      interval_ms when is_integer(interval_ms) ->
        interval_ms
        |> max(@debugger_auto_fire_min_refresh_interval_ms)
        |> min(@debugger_auto_fire_refresh_interval_ms)

      _ ->
        @debugger_auto_fire_refresh_interval_ms
    end
  end

  @spec debugger_auto_fire_enabled?(Project.t(), wire_input()) :: boolean()
  defp debugger_auto_fire_enabled?(%Project{} = project, target) do
    settings = project.debugger_settings || %{}
    auto_fire = Map.get(settings, "auto_fire", %{})
    Map.get(auto_fire, debugger_auto_fire_target(target)) == true
  end

  @spec debugger_auto_fire_target(wire_input()) :: String.t()
  defp debugger_auto_fire_target("protocol"), do: "protocol"
  defp debugger_auto_fire_target("companion"), do: "phone"
  defp debugger_auto_fire_target(:protocol), do: "protocol"
  defp debugger_auto_fire_target(:companion), do: "phone"
  defp debugger_auto_fire_target(_target), do: "watch"

  @spec debugger_checkbox_enabled?(wire_input()) :: boolean()
  defp debugger_checkbox_enabled?(value) when value in [true, "true", "on", "1", 1], do: true
  defp debugger_checkbox_enabled?(_value), do: false

  defp external_emulator_blocked?(socket) do
    socket.assigns.emulator_mode == "external" and not EmulatorSupport.external_mode_enabled?()
  end
end
