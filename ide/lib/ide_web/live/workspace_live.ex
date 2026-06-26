defmodule IdeWeb.WorkspaceLive do
  @moduledoc """
  Project workspace LiveView: thin facade over pane `*Flow` modules.

  See `ide/docs/workspace-live-flows.md` for event/async routing.
  """

  use IdeWeb, :live_view

  alias Ide.Projects
  alias Ide.Projects.Project
  alias Ide.Settings
  alias IdeWeb.WorkspaceLive.EditorPage
  alias IdeWeb.WorkspaceLive.EditorSupport
  alias IdeWeb.WorkspaceLive.EditorFlow
  alias IdeWeb.WorkspaceLive.ProjectSettingsFlow
  alias IdeWeb.WorkspaceLive.PublishPaneFlow
  alias IdeWeb.WorkspaceLive.EmulatorPage
  alias IdeWeb.WorkspaceLive.EmulatorFlow
  alias IdeWeb.WorkspaceLive.BuildPage
  alias IdeWeb.WorkspaceLive.BuildFlow
  alias IdeWeb.WorkspaceLive.PublishFlow
  alias IdeWeb.WorkspaceLive.PublishPage
  alias IdeWeb.WorkspaceLive.ProjectSettingsPage
  alias IdeWeb.WorkspaceLive.PackagesPage
  alias IdeWeb.WorkspaceLive.ResourcesPage
  alias IdeWeb.WorkspaceLive.ResourcesFlow
  alias IdeWeb.WorkspaceLive.PackagesFlow
  alias Ide.Debugger.RuntimeBackgroundNotify
  alias IdeWeb.WorkspaceLive.DebuggerSupport
  alias IdeWeb.WorkspaceLive.DebuggerFlow
  alias IdeWeb.WorkspaceLive.DebuggerPage
  alias IdeWeb.WorkspaceLive.State
  alias IdeWeb.WorkspaceLive.EditorDependencies
  alias IdeWeb.WorkspaceLive.Assigns, as: SocketAssigns
  alias IdeWeb.WorkspaceLive.Types

  alias Phoenix.LiveView.Rendered

  @type socket :: Phoenix.LiveView.Socket.t()
  @type lv_mount :: {:ok, socket()}
  @type lv_noreply :: {:noreply, socket()}
  @type assigns :: SocketAssigns.t()
  @type wire_input :: String.t() | integer() | float() | boolean() | nil | [wire_input()]
  @type pane :: atom()
  @type dependency_row :: EditorDependencies.dependency_row()

  @valid_resource_views ~w(
    bitmaps-static
    bitmaps-animated
    vectors-static
    vectors-animated
    fonts
    speaker-samples
  )

  @editor_flow_events EditorFlow.editor_events() ++ EditorFlow.file_tab_events()
  @resource_flow_events ResourcesFlow.resource_events()
  @build_flow_events BuildFlow.build_events()
  @build_flow_asyncs BuildFlow.build_asyncs()
  @emulator_flow_events EmulatorFlow.emulator_events()
  @project_settings_events ProjectSettingsFlow.settings_events()
  @publish_pane_events PublishPaneFlow.publish_events()
  @editor_flow_asyncs EditorFlow.editor_asyncs()
  @emulator_flow_asyncs EmulatorFlow.emulator_asyncs()
  @publish_flow_asyncs PublishPaneFlow.publish_asyncs()
  @settings_flow_asyncs ProjectSettingsFlow.settings_asyncs()
  @packages_flow_asyncs PackagesFlow.packages_asyncs()

  @impl true
  @spec mount(Types.wire_params(), Types.session_params(), socket()) :: lv_mount()
  def mount(_params, _session, socket) do
    settings = Settings.current()

    {:ok, State.mount_defaults(socket, settings, EmulatorFlow.default_emulator_target())}
  end

  @impl true
  @spec handle_params(Types.wire_params(), String.t(), socket()) :: lv_noreply()
  def handle_params(%{"slug" => slug} = params, _uri, socket) do
    case Projects.get_project_by_slug(slug, socket.assigns.current_user) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Unknown project: #{slug}")
         |> push_navigate(to: ~p"/projects")}

      project ->
        previous_pane = socket.assigns[:pane]

        socket =
          socket
          |> assign_resource_view(params)

        cond do
          socket.assigns.live_action == :resources and is_nil(Map.get(params, "resource_view")) ->
            {:noreply, push_patch(socket, to: ~p"/projects/#{slug}/resources/bitmaps-static")}

          State.pane_only_navigation?(socket, project) ->
            {:noreply,
             socket
             |> State.assign_pane_switch(project, previous_pane)
             |> EditorSupport.maybe_open_editor_default_file(project, previous_pane)
             |> maybe_refresh_debugger()
             |> EmulatorFlow.maybe_check_emulator_installation()
             |> DebuggerFlow.maybe_schedule_debugger_auto_fire_refresh()}

          true ->
            {:noreply, load_workspace_project(socket, project, previous_pane)}
        end
    end
  end

  defp assign_resource_view(socket, params) when is_map(params) do
    view =
      case Map.get(params, "resource_view") do
        v when v in @valid_resource_views -> v
        _ -> "bitmaps-static"
      end

    assign(socket, :resource_view, view)
  end

  @spec load_workspace_project(socket(), Projects.Project.t(), pane() | nil) :: socket()
  defp load_workspace_project(socket, project, previous_pane) do
    settings = Settings.current()
    _ = Projects.ensure_bitmap_generated(project)

    tree = Projects.list_source_tree(project)
    {bitmap_resources, bitmap_resources_error} = ResourcesFlow.load_bitmap_resources(project)
    vector_resources = ResourcesFlow.load_vector_resources(project)
    animation_resources = ResourcesFlow.load_animation_resources(project)
    speaker_samples = ResourcesFlow.load_speaker_samples(project)
    font_sources = ResourcesFlow.load_font_sources(project)
    font_resources = ResourcesFlow.load_font_resources(project)
    screenshots = ResourcesFlow.load_screenshots(project)
    screenshot_groups = ResourcesFlow.group_screenshots(screenshots)

    publish_readiness = PublishFlow.publish_readiness(project, screenshots)

    selected_emulator_target = EmulatorFlow.project_emulator_target(project)
    emulator_mode = EmulatorFlow.project_emulator_mode(project)
    emulator_production_build = EmulatorFlow.project_emulator_production_build(project)

    project_data = %{
      tree: tree,
      bitmap_resources: bitmap_resources,
      bitmap_resources_error: bitmap_resources_error,
      vector_resources: vector_resources,
      animation_resources: animation_resources,
      speaker_samples: speaker_samples,
      font_sources: font_sources,
      font_resources: font_resources,
      screenshots: screenshots,
      screenshot_groups: screenshot_groups,
      publish_readiness: publish_readiness,
      selected_emulator_target: selected_emulator_target,
      emulator_mode: emulator_mode,
      emulator_production_build: emulator_production_build,
      packages_target_root: EditorSupport.preferred_packages_target_root(socket, project),
      debugger_timeline_mode: DebuggerFlow.project_debugger_timeline_mode(project),
      companion_app_present: Projects.companion_app_present?(project)
    }

    socket
    |> State.assign_project(project, settings, project_data)
    |> subscribe_debugger_runtime_updates(project)
    |> EditorSupport.maybe_initialize_forms(project)
    |> EditorSupport.maybe_open_editor_default_file(project, previous_pane)
    |> EditorSupport.refresh_editor_dependencies()
    |> maybe_refresh_debugger()
    |> EmulatorFlow.maybe_check_emulator_installation()
    |> DebuggerFlow.maybe_schedule_debugger_auto_fire_refresh()
    |> ProjectSettingsFlow.refresh_github_repo_status()
  end

  @spec subscribe_debugger_runtime_updates(socket(), Project.t()) :: socket()
  defp subscribe_debugger_runtime_updates(socket, %Project{} = project) do
    if connected?(socket) do
      topic = RuntimeBackgroundNotify.topic(Projects.scope_key(project))
      old_topic = socket.assigns[:debugger_runtime_pubsub_topic]

      socket =
        if old_topic == topic do
          socket
        else
          if is_binary(old_topic), do: Phoenix.PubSub.unsubscribe(Ide.PubSub, old_topic)
          :ok = Phoenix.PubSub.subscribe(Ide.PubSub, topic)
          assign(socket, :debugger_runtime_pubsub_topic, topic)
        end

      socket
    else
      socket
    end
  end

  @impl true
  @spec handle_event(String.t(), Types.event_params(), socket()) :: lv_noreply()
  def handle_event(event, params, socket) when event in @editor_flow_events do
    EditorFlow.handle_event(event, params, socket)
  end

  def handle_event(event, params, socket) when event in @resource_flow_events do
    ResourcesFlow.handle_event(event, params, socket)
  end

  def handle_event(event, params, socket) when event in @build_flow_events do
    BuildFlow.handle_event(event, params, socket)
  end

  def handle_event("debugger-" <> _rest = event, params, socket) do
    DebuggerFlow.handle_event(event, params, socket)
  end

  def handle_event("simulator-save-settings", params, socket) do
    DebuggerFlow.handle_simulator_save_settings_event(params, socket)
  end

  def handle_event("packages-" <> _rest = event, params, socket) do
    PackagesFlow.handle_event(event, params, socket)
  end

  def handle_event(event, params, socket) when event in @emulator_flow_events do
    EmulatorFlow.handle_event(event, params, socket)
  end

  def handle_event(event, params, socket) when event in @project_settings_events do
    ProjectSettingsFlow.handle_event(event, params, socket)
  end

  def handle_event(event, params, socket) when event in @publish_pane_events do
    PublishPaneFlow.handle_event(event, params, socket)
  end

  @impl true
  @spec handle_async(atom(), Types.async_result(), socket()) :: lv_noreply()
  def handle_async(:debugger_bootstrap, result, socket),
    do: DebuggerFlow.handle_async(:debugger_bootstrap, result, socket)

  def handle_async(async, result, socket) when async in @build_flow_asyncs do
    BuildFlow.handle_async(async, result, socket)
  end

  def handle_async(async, result, socket) when async in @editor_flow_asyncs do
    EditorFlow.handle_async(async, result, socket)
  end

  def handle_async(async, result, socket) when async in @emulator_flow_asyncs do
    EmulatorFlow.handle_async(async, result, socket)
  end

  def handle_async(async, result, socket) when async in @publish_flow_asyncs do
    PublishPaneFlow.handle_async(async, result, socket)
  end

  def handle_async(async, result, socket) when async in @settings_flow_asyncs do
    ProjectSettingsFlow.handle_async(async, result, socket)
  end

  def handle_async(async, result, socket) when async in @packages_flow_asyncs do
    PackagesFlow.handle_async(async, result, socket)
  end

  @impl true
  def handle_info(msg, socket) do
    route_info(msg, socket)
  end

  @type routed_info_message :: Types.info_message() | Types.liveview_system_message()

  @spec route_info(routed_info_message(), socket()) :: lv_noreply()
  defp route_info({:companion_debugger_bootstrapped, _, _} = msg, socket),
    do: DebuggerFlow.handle_info(msg, socket)

  defp route_info({:debugger_bootstrap_progress, _, _} = msg, socket),
    do: DebuggerFlow.handle_info(msg, socket)

  defp route_info({:debugger_companion_bootstrap_progress, message} = msg, socket)
       when is_binary(message),
       do: DebuggerFlow.handle_info(msg, socket)

  defp route_info(:debugger_runtime_updated = msg, socket),
    do: DebuggerFlow.handle_info(msg, socket)

  defp route_info({:debugger_runtime_refresh, seq} = msg, socket) when is_integer(seq),
    do: DebuggerFlow.handle_info(msg, socket)

  defp route_info({:debugger_auto_fire_refresh, _} = msg, socket),
    do: DebuggerFlow.handle_info(msg, socket)

  defp route_info({:capture_all_progress, _, _} = msg, socket),
    do: EmulatorFlow.handle_info(msg, socket)

  defp route_info({:packages_search_progress, _, _} = msg, socket),
    do: PackagesFlow.handle_info(msg, socket)

  defp route_info(_msg, socket), do: {:noreply, socket}

  @impl true
  @spec render(assigns()) :: Rendered.t()
  def render(assigns) do
    ~H"""
    <div
      id="workspace-live-root"
      class="flex h-screen w-full max-w-none flex-col p-4"
      phx-hook="DebuggerShortcuts"
      data-pane={Atom.to_string(@pane)}
    >
      <div
        id="firebase-auth-refresh"
        phx-hook="FirebaseAuthRefresh"
        class="hidden"
        data-firebase-config={Jason.encode!(@firebase_config)}
      >
      </div>
      <header class="mb-4 flex items-center justify-between gap-3 rounded-lg border border-zinc-200 bg-white px-4 py-3 shadow-sm">
        <div class="flex min-w-0 flex-1 items-center gap-3">
          <.link
            navigate={~p"/projects"}
            class="inline-flex h-9 w-9 items-center justify-center rounded bg-zinc-100 text-base font-semibold text-zinc-700 hover:bg-zinc-200"
            title="Back to projects"
          >
            &lt;
          </.link>
          <div class="min-w-0">
            <h1 class="truncate text-lg font-semibold">{@project.name}</h1>
            <p class="truncate text-sm text-zinc-600">
              Target: {@project.target_type} · Slug: {@project.slug}
            </p>
          </div>
        </div>
        <div class="flex items-center gap-2 text-sm">
          <.link patch={~p"/projects/#{@project.slug}/editor"} class={pane_class(@pane, :editor)}>
            Editor
          </.link>
          <.link patch={~p"/projects/#{@project.slug}/debugger"} class={pane_class(@pane, :debugger)}>
            Debugger
          </.link>
          <.link patch={~p"/projects/#{@project.slug}/build"} class={pane_class(@pane, :build)}>
            Build
          </.link>
          <.link patch={~p"/projects/#{@project.slug}/emulator"} class={pane_class(@pane, :emulator)}>
            Emulator
          </.link>
          <.link patch={~p"/projects/#{@project.slug}/publish"} class={pane_class(@pane, :publish)}>
            Publish
          </.link>
          <.link patch={~p"/projects/#{@project.slug}/settings"} class={pane_class(@pane, :settings)}>
            Project settings
          </.link>
        </div>
        <.link
          navigate={EditorSupport.settings_path_with_return_to("/projects/#{@project.slug}/#{@pane}")}
          class="inline-flex h-9 w-9 items-center justify-center rounded bg-zinc-100 text-zinc-700 hover:bg-zinc-200"
          title="IDE settings"
        >
          <.icon name="hero-cog-6-tooth-mini" class="h-5 w-5" />
          <span class="sr-only">Settings</span>
        </.link>
      </header>

      {EditorPage.render(assigns)}

      {ResourcesPage.render(assigns)}

      {PackagesPage.render(assigns)}

      {BuildPage.render(assigns)}
      {PublishPage.render(assigns)}
      {ProjectSettingsPage.render(assigns)}

      {DebuggerPage.render(assigns)}

      {EmulatorPage.render(assigns)}
    </div>
    """
  end

  @spec pane_class(pane(), pane()) :: String.t()
  defp pane_class(active, pane) when active == pane,
    do: "rounded bg-blue-100 px-3 py-2 text-blue-800"

  defp pane_class(_active, _pane), do: "rounded bg-zinc-100 px-3 py-2"

  @spec maybe_refresh_debugger(socket()) :: socket()
  defp maybe_refresh_debugger(socket) do
    if socket.assigns[:pane] == :debugger do
      socket =
        socket
        |> DebuggerFlow.maybe_ensure_companion_bootstrapped()

      if Phoenix.LiveView.connected?(socket) do
        DebuggerFlow.schedule_debugger_runtime_refresh(socket)
      else
        DebuggerSupport.refresh(socket)
      end
    else
      socket
    end
  end
end
