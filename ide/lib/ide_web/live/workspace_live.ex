defmodule IdeWeb.WorkspaceLive do
  use IdeWeb, :live_view

  alias Ide.Formatter
  alias Ide.Formatter.EditPatch
  alias Ide.Compiler
  alias Ide.GitHub.Push, as: GitHubPush
  alias Ide.Emulator
  alias Ide.PebblePreferences
  alias Ide.PebbleToolchain
  alias Ide.Packages
  alias Ide.PublishManifest
  alias Ide.PublishReadiness
  alias Ide.Projects
  alias Ide.Projects.Project
  alias Ide.Resources.ResourceStore
  alias Ide.Settings
  alias Ide.Screenshots
  alias Ide.EditorCompletion
  alias Ide.EditorDocLinks
  alias Ide.Markdown
  alias IdeWeb.WorkspaceLive.EditorPage
  alias IdeWeb.WorkspaceLive.EditorSupport
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
  alias IdeWeb.WorkspaceLive.DebuggerSupport
  alias IdeWeb.WorkspaceLive.DebuggerPage
  alias IdeWeb.WorkspaceLive.State
  alias IdeWeb.WorkspaceLive.ToolchainPresenter

  @debugger_auto_fire_refresh_interval_ms 1_000
  @debugger_auto_fire_min_refresh_interval_ms 100

  @impl true
  @spec mount(term(), term(), term()) :: term()
  def mount(_params, _session, socket) do
    settings = Settings.current()

    {:ok, State.mount_defaults(socket, settings, default_emulator_target())}
  end

  @impl true
  @spec handle_params(term(), term(), term()) :: term()
  def handle_params(%{"slug" => slug}, _uri, socket) do
    case Projects.get_project_by_slug(slug) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Unknown project: #{slug}")
         |> push_navigate(to: ~p"/projects")}

      project ->
        settings = Settings.current()
        previous_pane = socket.assigns[:pane]
        _ = Projects.ensure_bitmap_generated(project)
        tree = Projects.list_source_tree(project)
        bitmap_resources = load_bitmap_resources(project)
        font_sources = load_font_sources(project)
        font_resources = load_font_resources(project)
        screenshots = load_screenshots(project)
        screenshot_groups = group_screenshots(screenshots)

        publish_readiness = PublishFlow.publish_readiness(screenshots)

        selected_emulator_target = project_emulator_target(project)
        emulator_mode = project_emulator_mode(project)

        project_data = %{
          tree: tree,
          bitmap_resources: bitmap_resources,
          font_sources: font_sources,
          font_resources: font_resources,
          screenshots: screenshots,
          screenshot_groups: screenshot_groups,
          publish_readiness: publish_readiness,
          selected_emulator_target: selected_emulator_target,
          emulator_mode: emulator_mode,
          packages_target_root: preferred_packages_target_root(socket, project),
          debugger_timeline_mode: project_debugger_timeline_mode(project),
          companion_app_present: Projects.companion_app_present?(project)
        }

        {:noreply,
         socket
         |> State.assign_project(project, settings, project_data)
         |> maybe_initialize_forms(project)
         |> maybe_open_editor_default_file(project, previous_pane)
         |> refresh_editor_dependencies()
         |> maybe_refresh_debugger()
         |> maybe_check_emulator_installation()
         |> maybe_schedule_debugger_auto_fire_refresh()}
    end
  end

  @impl true
  @spec handle_event(term(), term(), term()) :: term()
  def handle_event("open-file", %{"source-root" => source_root, "rel-path" => rel_path}, socket) do
    tab_id = tab_id(source_root, rel_path)
    existing_tab = Enum.find(socket.assigns.tabs, &(&1.id == tab_id))

    if existing_tab do
      existing_tab = refresh_tab_read_only(existing_tab)
      selected_state = existing_tab.editor_state || %{}

      {:noreply,
       socket
       |> update_tab_by_id(tab_id, fn _tab -> existing_tab end)
       |> assign(:active_tab_id, tab_id)
       |> assign(:opening_file_id, nil)
       |> assign(:opening_file_label, nil)
       |> assign(:file_open_token, nil)
       |> assign(:active_diagnostic_index, selected_state[:active_diagnostic_index])
       |> assign_tokenization(existing_tab.content, existing_tab.rel_path)
       |> restore_editor_state(selected_state)}
    else
      project = socket.assigns.project
      token = System.unique_integer([:positive])

      {:noreply,
       socket
       |> assign(:opening_file_id, tab_id)
       |> assign(:opening_file_label, editor_file_tree_label(source_root, rel_path))
       |> assign(:file_open_token, token)
       |> start_async(:open_file, fn ->
         {Projects.read_source_file(project, source_root, rel_path), token, source_root, rel_path}
       end)}
    end
  end

  def handle_event(
        "toggle-tree-dir",
        %{"source-root" => source_root, "rel-path" => rel_path},
        socket
      ) do
    key = tree_dir_key(source_root, rel_path)
    expanded = socket.assigns.expanded_tree_dirs || MapSet.new()

    next_expanded =
      if MapSet.member?(expanded, key) do
        MapSet.delete(expanded, key)
      else
        MapSet.put(expanded, key)
      end

    {:noreply, assign(socket, :expanded_tree_dirs, next_expanded)}
  end

  def handle_event(
        "new-file",
        %{"new_file" => %{"source_root" => source_root, "rel_path" => rel_path}},
        socket
      ) do
    project = socket.assigns.project
    rel_path = normalize_editor_src_rel_path(rel_path)

    with :ok <- validate_creatable_source_root(project, source_root),
         {:ok, module_name} <- module_name_from_rel_path(rel_path),
         :ok <- validate_new_elm_module_name(module_name),
         :ok <-
           Projects.write_source_file(
             project,
             source_root,
             rel_path,
             new_elm_module_template(module_name)
           ) do
      {:noreply,
       socket
       |> assign(:create_file_modal_open, false)
       |> put_flash(:info, "Created #{editor_source_display_path(rel_path)}")
       |> refresh_tree()}
    else
      {:error, :invalid_rel_path} ->
        {:noreply, put_flash(socket, :error, "Please enter a valid file path.")}

      {:error, :invalid_extension} ->
        {:noreply, put_flash(socket, :error, "New files must use the .elm extension.")}

      {:error, :invalid_module_name} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Elm module names must use slash-separated segments that each start with a capital letter."
         )}

      {:error, :invalid_source_root} ->
        {:noreply, put_flash(socket, :error, "Please choose an editable source root.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not create file: #{inspect(reason)}")}
    end
  end

  def handle_event("rename-file", %{"rename" => %{"new_rel_path" => new_rel_path}}, socket) do
    new_rel_path = normalize_editor_src_rel_path(new_rel_path)

    with %{source_root: source_root, rel_path: old_rel_path} = active <- active_tab(socket),
         :ok <- ensure_can_modify_editor_file(active),
         :ok <-
           Projects.rename_source_path(
             socket.assigns.project,
             source_root,
             old_rel_path,
             new_rel_path
           ) do
      tabs =
        Enum.map(socket.assigns.tabs, fn tab ->
          if tab.id == socket.assigns.active_tab_id do
            %{tab | id: tab_id(source_root, new_rel_path), rel_path: new_rel_path}
          else
            tab
          end
        end)

      {:noreply,
       socket
       |> assign(:rename_file_modal_open, false)
       |> assign(:tabs, tabs)
       |> assign(:active_tab_id, tab_id(source_root, new_rel_path))
       |> refresh_tree()
       |> put_flash(:info, "Renamed file.")}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Open a file first.")}

      {:error, :read_only_file} ->
        {:noreply, put_flash(socket, :error, "Generated files are read-only.")}

      {:error, :protected_file} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Main.elm, Companion/Types.elm, and Pebble/Ui/Resources.elm cannot be renamed."
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not rename file: #{inspect(reason)}")}
    end
  end

  def handle_event("delete-file", _params, socket) do
    case active_tab(socket) do
      nil ->
        {:noreply, put_flash(socket, :error, "Open a file first.")}

      %{source_root: source_root, rel_path: rel_path, id: id} = tab ->
        case ensure_can_modify_editor_file(tab) do
          :ok ->
            case Projects.delete_source_path(socket.assigns.project, source_root, rel_path) do
              :ok ->
                tabs = Enum.reject(socket.assigns.tabs, &(&1.id == id))
                next_active = List.first(tabs)
                next_state = (next_active && next_active.editor_state) || %{}

                {:noreply,
                 socket
                 |> assign(:tabs, tabs)
                 |> assign(:active_tab_id, next_active && next_active.id)
                 |> assign(:active_diagnostic_index, next_state[:active_diagnostic_index])
                 |> assign_tokenization(
                   next_active && next_active.content,
                   next_active && next_active.rel_path
                 )
                 |> restore_editor_state(next_state)
                 |> refresh_tree()
                 |> put_flash(:info, "Deleted #{editor_source_display_path(rel_path)}")}

              {:error, reason} ->
                {:noreply, put_flash(socket, :error, "Could not delete file: #{inspect(reason)}")}
            end

          {:error, :read_only_file} ->
            {:noreply, put_flash(socket, :error, "Generated files are read-only.")}

          {:error, :protected_file} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "Main.elm, Companion/Types.elm, and Pebble/Ui/Resources.elm cannot be deleted."
             )}
        end
    end
  end

  def handle_event("select-tab", %{"id" => id}, socket) do
    socket =
      update_tab_by_id(socket, id, fn tab ->
        refresh_tab_read_only(tab)
      end)

    selected_tab = Enum.find(socket.assigns.tabs, &(&1.id == id))
    selected_state = (selected_tab && selected_tab.editor_state) || %{}

    {:noreply,
     socket
     |> assign(:active_tab_id, id)
     |> assign(:active_diagnostic_index, selected_state[:active_diagnostic_index])
     |> assign_tokenization(
       selected_tab && selected_tab.content,
       selected_tab && selected_tab.rel_path
     )
     |> restore_editor_state(selected_state)}
  end

  def handle_event("close-tab", %{"id" => id}, socket) do
    tabs = Enum.reject(socket.assigns.tabs, &(&1.id == id))

    next_active =
      if socket.assigns.active_tab_id == id, do: List.first(tabs), else: active_tab(socket)

    next_state = (next_active && next_active.editor_state) || %{}

    {:noreply,
     socket
     |> assign(tabs: tabs, active_tab_id: next_active && next_active.id)
     |> assign(:active_diagnostic_index, next_state[:active_diagnostic_index])
     |> assign_tokenization(
       next_active && next_active.content,
       next_active && next_active.rel_path
     )
     |> restore_editor_state(next_state)}
  end

  def handle_event("editor-change", %{"editor" => %{"content" => content}}, socket) do
    active = active_tab(socket)
    active_rel_path = active && active.rel_path

    cond do
      read_only_tab?(active) ->
        {:noreply, socket}

      active && active.content == content ->
        {:noreply, socket}

      true ->
        {:noreply,
         socket
         |> update_tab(fn tab -> %{tab | content: content, dirty: true} end)
         |> assign_tokenization(content, active_rel_path)
         |> clear_editor_check(active)}
    end
  end

  def handle_event("editor-change", %{"content" => content}, socket) do
    active = active_tab(socket)
    active_rel_path = active && active.rel_path

    cond do
      read_only_tab?(active) ->
        {:noreply, socket}

      active && active.content == content ->
        {:noreply, socket}

      true ->
        {:noreply,
         socket
         |> update_tab(fn tab -> %{tab | content: content, dirty: true} end)
         |> assign_tokenization(content, active_rel_path)
         |> clear_editor_check(active)}
    end
  end

  def handle_event(
        "editor-key-edit",
        %{
          "key" => key,
          "content" => content,
          "selection_start" => raw_start,
          "selection_end" => raw_end
        } = params,
        socket
      ) do
    if semantic_edit_ops_enabled?() and not read_only_tab?(active_tab(socket)) do
      start_offset = parse_non_negative_int(raw_start) || 0
      end_offset = parse_non_negative_int(raw_end) || start_offset
      shift_key = Map.get(params, "shift_key", false) in [true, "true", "1", 1]

      edit_result =
        case key do
          "tab" -> Formatter.compute_tab_edit(content, start_offset, end_offset, shift_key)
          "enter" -> Formatter.compute_enter_edit(content, start_offset, end_offset)
          _ -> identity_edit_patch(content, start_offset, end_offset)
        end

      active = active_tab(socket)
      active_rel_path = active && active.rel_path
      next_content = apply_text_patch(content, edit_result)

      {:noreply,
       socket
       |> update_tab(fn tab -> %{tab | content: next_content, dirty: true} end)
       |> assign_tokenization(next_content, active_rel_path)
       |> clear_editor_check(active)
       |> push_event("token-editor-apply-edit", edit_result)}
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "editor-request-completions",
        %{
          "content" => content,
          "selection_start" => raw_start,
          "selection_end" => raw_end
        },
        socket
      ) do
    if read_only_tab?(active_tab(socket)) do
      {:noreply, socket}
    else
      start_offset = parse_non_negative_int(raw_start) || 0
      end_offset = parse_non_negative_int(raw_end) || start_offset
      cursor = max(start_offset, end_offset)
      {replace_from, replace_to, prefix} = completion_replace_range(content, cursor)

      items =
        EditorCompletion.suggest(%{
          prefix: prefix,
          parser_payload: socket.assigns[:formatter_parser_payload],
          token_tokens: socket.assigns[:token_tokens],
          package_doc_index: socket.assigns[:package_doc_index],
          editor_doc_packages: socket.assigns[:editor_doc_packages],
          direct_dependencies: socket.assigns[:project_elm_direct],
          indirect_dependencies: socket.assigns[:project_elm_indirect],
          limit: 24
        })

      {:noreply,
       push_event(socket, "token-editor-show-completions", %{
         replace_from: replace_from,
         replace_to: replace_to,
         items:
           Enum.map(items, fn item ->
             %{label: item.label, insert_text: item.insert_text}
           end)
       })}
    end
  end

  def handle_event("editor-submit", %{"editor_action" => "format"} = params, socket) do
    handle_event("format-file", params, socket)
  end

  def handle_event("editor-submit", params, socket) do
    handle_event("save-file", params, socket)
  end

  def handle_event("format-file", params, socket) do
    case active_tab(socket) do
      nil ->
        {:noreply, put_flash(socket, :error, "No active file to format.")}

      tab ->
        tab = tab_with_save_content(tab, params)

        if read_only_tab?(tab) do
          {:noreply, put_flash(socket, :error, "Generated files are read-only.")}
        else
          if elm_source_file?(tab.rel_path) do
            project = socket.assigns.project
            parser_payload = socket.assigns[:formatter_parser_payload]
            tokens = socket.assigns[:token_tokens]
            formatter_backend = socket.assigns.formatter_backend

            {:noreply,
             socket
             |> assign(:format_status, :running)
             |> assign(:format_output, nil)
             |> start_async(:format_file, fn ->
               case format_source(project, tab, formatter_backend, parser_payload, tokens) do
                 {:ok, result} ->
                   write_result =
                     Projects.write_source_file(
                       project,
                       tab.source_root,
                       tab.rel_path,
                       result.formatted_source
                     )

                   {:ok, %{tab: tab, result: result, write_result: write_result}}

                 {:error, reason} ->
                   {:error, %{tab: tab, reason: reason}}
               end
             end)}
          else
            {:noreply,
             socket
             |> assign(:format_status, :idle)
             |> assign(:format_output, "Format is currently supported for .elm files only.")
             |> put_flash(:info, "Format skipped: only .elm files are supported.")}
          end
        end
    end
  end

  def handle_event("save-file", params, socket) do
    case active_tab(socket) do
      nil ->
        {:noreply, put_flash(socket, :error, "No active file to save.")}

      tab ->
        if read_only_tab?(tab) do
          {:noreply, put_flash(socket, :error, "Generated files are read-only.")}
        else
          tab = tab_with_save_content(tab, params)

          {content_to_save, flash_message, format_output, auto_format_last_result} =
            prepare_content_for_save(
              socket.assigns.project,
              tab,
              socket.assigns.auto_format_on_save,
              socket.assigns.formatter_backend,
              socket.assigns[:formatter_parser_payload],
              socket.assigns[:token_tokens]
            )

          case Projects.write_source_file(
                 socket.assigns.project,
                 tab.source_root,
                 tab.rel_path,
                 content_to_save
               ) do
            :ok ->
              socket =
                DebuggerSupport.maybe_reload(
                  socket,
                  tab.rel_path,
                  content_to_save,
                  "file_saved",
                  tab.source_root
                )

              socket = maybe_regenerate_phone_preferences_after_save(socket, tab)

              socket =
                socket
                |> update_tab(fn active -> %{active | dirty: false, content: content_to_save} end)
                |> assign(:format_output, format_output)
                |> assign(:auto_format_last_result, auto_format_last_result)
                |> assign_tokenization(content_to_save, tab.rel_path, mode: :compiler)

              socket =
                if debugger_session_active?(socket) do
                  schedule_compiler_check(socket)
                else
                  socket
                end

              socket = schedule_editor_check(socket, tab)

              {:noreply, put_flash(socket, :info, flash_message)}

            {:error, reason} ->
              {:noreply, put_flash(socket, :error, "Could not save file: #{inspect(reason)}")}
          end
        end
    end
  end

  def handle_event("upload-bitmap-resource", _params, socket) do
    project = socket.assigns.project

    results =
      consume_uploaded_entries(socket, :bitmap, fn %{path: path}, entry ->
        case Projects.import_bitmap_resource(project, path, entry.client_name) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:ok, %{error: inspect(reason)}}
        end
      end)

    socket =
      socket
      |> assign(:bitmap_resources, load_bitmap_resources(project))
      |> assign(:bitmap_upload_output, bitmap_upload_output(results))
      |> refresh_tree()

    {:noreply, socket}
  end

  def handle_event("validate-resource-upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("delete-bitmap-resource", %{"ctor" => ctor}, socket) do
    case Projects.delete_bitmap_resource(socket.assigns.project, ctor) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:bitmap_resources, load_bitmap_resources(socket.assigns.project))
         |> refresh_tree()
         |> put_flash(:info, "Deleted bitmap #{ctor}.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not delete bitmap: #{inspect(reason)}")}
    end
  end

  def handle_event("upload-font-resource", _params, socket) do
    project = socket.assigns.project

    results =
      consume_uploaded_entries(socket, :font, fn %{path: path}, entry ->
        case Projects.import_font_resource(project, path, entry.client_name) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:ok, %{error: inspect(reason)}}
        end
      end)

    socket =
      socket
      |> assign(:font_resources, load_font_resources(project))
      |> assign(:font_sources, load_font_sources(project))
      |> assign(:font_upload_output, font_upload_output(results))
      |> refresh_tree()

    {:noreply, socket}
  end

  def handle_event("add-font-variant", %{"variant" => params}, socket) do
    project = socket.assigns.project

    case Projects.add_font_variant(project, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:font_sources, load_font_sources(project))
         |> assign(:font_resources, load_font_resources(project))
         |> refresh_tree()
         |> put_flash(:info, "Added font identifier.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not add font identifier: #{inspect(reason)}")}
    end
  end

  def handle_event("update-font-variant", %{"ctor" => ctor, "variant" => params}, socket) do
    project = socket.assigns.project

    case Projects.update_font_variant(project, ctor, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:font_sources, load_font_sources(project))
         |> assign(:font_resources, load_font_resources(project))
         |> refresh_tree()
         |> put_flash(:info, "Updated font #{ctor}.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not update font: #{inspect(reason)}")}
    end
  end

  def handle_event("delete-font-resource", %{"ctor" => ctor}, socket) do
    case Projects.delete_font_resource(socket.assigns.project, ctor) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:font_sources, load_font_sources(socket.assigns.project))
         |> assign(:font_resources, load_font_resources(socket.assigns.project))
         |> refresh_tree()
         |> put_flash(:info, "Deleted font #{ctor}.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not delete font: #{inspect(reason)}")}
    end
  end

  def handle_event("delete-font-source", %{"source-id" => source_id}, socket) do
    case Projects.delete_font_source(socket.assigns.project, source_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:font_sources, load_font_sources(socket.assigns.project))
         |> assign(:font_resources, load_font_resources(socket.assigns.project))
         |> refresh_tree()
         |> put_flash(:info, "Deleted source font.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not delete source font: #{inspect(reason)}")}
    end
  end

  def handle_event(event, params, socket)
      when event in [
             "run-check",
             "run-build",
             "run-compile",
             "run-manifest",
             "set-manifest-strict"
           ] do
    BuildFlow.handle_event(event, params, socket)
  end

  def handle_event("packages-search", params, socket) do
    search_params = Map.get(params, "packages_search") || %{}
    query = Map.get(search_params, "query", "") |> String.trim()

    if query == "" do
      {:noreply,
       socket
       |> assign(:packages_query, "")
       |> assign(:packages_search_results, [])
       |> assign(:packages_search_total, 0)
       |> assign(:packages_search_busy, false)
       |> assign(:packages_search_progress, nil)
       |> assign(:packages_search_token, nil)
       |> assign(:packages_inspect_loading, nil)
       |> PackagesFlow.maybe_select_first_package()}
    else
      search_token = make_ref()
      lv = self()

      progress_fn = fn msg ->
        send(lv, {:packages_search_progress, search_token, msg})
      end

      packages_target_root = socket.assigns.packages_target_root

      platform_target =
        case packages_target_root do
          "phone" -> :phone
          _ -> :watch
        end

      {:noreply,
       socket
       |> assign(:packages_search_token, search_token)
       |> assign(:packages_search_busy, true)
       |> assign(
         :packages_search_progress,
         PackagesFlow.search_progress_label({:phase, :starting})
       )
       |> assign(:packages_query, query)
       |> assign(:packages_search_results, [])
       |> assign(:packages_search_total, 0)
       |> PackagesFlow.maybe_select_first_package()
       |> start_async(:packages_search, fn ->
         result =
           Packages.search(query,
             per_page: 30,
             progress: progress_fn,
             platform_target: platform_target
           )

         {result, search_token}
       end)}
    end
  end

  def handle_event("packages-select", %{"package" => package}, socket) do
    socket =
      socket
      |> assign(:packages_dep_docs_package, nil)
      |> assign(:packages_dep_docs_version, nil)
      |> assign(:packages_dep_readme, nil)

    {:noreply, PackagesFlow.schedule_inspection(socket, package)}
  end

  def handle_event(
        "packages-set-target-root",
        %{"packages_target" => %{"source_root" => source_root}},
        socket
      ) do
    source_root = PackagesFlow.sanitize_target_root(socket.assigns.project, source_root)

    socket =
      socket
      |> assign(:packages_target_root, source_root)
      |> refresh_editor_dependencies()
      |> PackagesFlow.refresh_preview()

    {:noreply, socket}
  end

  def handle_event("packages-add", %{"package" => package}, socket) do
    project = socket.assigns.project

    opts = [] |> maybe_put_kw(:source_root, socket.assigns.packages_target_root)

    case Packages.add_to_project(project, package, opts) do
      {:ok, result} ->
        message = "Added #{package} #{result.selected_version} to #{result.source_root}/elm.json"

        {:noreply,
         socket
         |> assign(:project, Map.get(result, :project, project))
         |> assign(:packages_last_add_result, result)
         |> refresh_tree()
         |> PackagesFlow.refresh_preview()
         |> put_flash(:info, message)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, package_add_error(reason))}
    end
  end

  def handle_event("packages-remove", %{"package" => package}, socket) do
    project = socket.assigns.project

    opts = [] |> maybe_put_kw(:source_root, socket.assigns.packages_target_root)

    case Packages.remove_from_project(project, package, opts) do
      {:ok, result} ->
        message = "Removed #{package} from #{result.source_root}/elm.json"

        {:noreply,
         socket
         |> assign(:packages_last_add_result, nil)
         |> refresh_tree()
         |> PackagesFlow.refresh_preview()
         |> put_flash(:info, message)}

      {:error, :builtin_package_not_removable} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Required packages (e.g. elm/core, elm/json, elm/time, Pebble) cannot be removed."
         )}

      {:error, {:package_in_use, package}} ->
        {:noreply,
         socket
         |> mark_dependency_used(package)
         |> put_flash(
           :error,
           "#{package} is imported by current Elm source files. Remove those imports before removing the package."
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not remove package: #{inspect(reason)}")}
    end
  end

  def handle_event("packages-dep-select", %{"package" => package, "version" => version}, socket) do
    readme =
      case Packages.readme(package, version, []) do
        {:ok, payload} ->
          payload.readme || ""

        _ ->
          "(Could not load README for #{package} #{version}.)"
      end

    {:noreply,
     socket
     |> assign(:packages_dep_docs_package, package)
     |> assign(:packages_dep_docs_version, version)
     |> assign(:packages_dep_readme, readme)}
  end

  def handle_event("open-create-file-modal", _params, socket) do
    project = socket.assigns.project
    source_roots = creatable_source_roots(project)

    {:noreply,
     socket
     |> assign(:create_file_modal_open, true)
     |> assign(:create_file_source_roots, source_roots)
     |> assign(
       :new_file_form,
       to_form(
         %{"source_root" => List.first(source_roots) || "watch", "rel_path" => ""},
         as: :new_file
       )
     )}
  end

  def handle_event("close-create-file-modal", _params, socket) do
    {:noreply, assign(socket, :create_file_modal_open, false)}
  end

  def handle_event("add-companion-app", _params, socket) do
    project = socket.assigns.project

    case Projects.add_companion_app(project) do
      :ok ->
        {:noreply,
         socket
         |> assign(:companion_app_present, true)
         |> put_flash(:info, "Added companion app and protocol files.")
         |> refresh_tree()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not add companion app: #{inspect(reason)}")}
    end
  end

  def handle_event("open-rename-file-modal", _params, socket) do
    case active_tab(socket) do
      nil ->
        {:noreply, put_flash(socket, :error, "Open a file first.")}

      tab ->
        case ensure_can_modify_editor_file(tab) do
          :ok ->
            {:noreply,
             socket
             |> assign(:rename_file_modal_open, true)
             |> assign(
               :rename_form,
               to_form(%{"new_rel_path" => editor_source_display_path(tab.rel_path)}, as: :rename)
             )}

          {:error, :read_only_file} ->
            {:noreply, put_flash(socket, :error, "Generated files are read-only.")}

          {:error, :protected_file} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "Main.elm, Companion/Types.elm, and Pebble/Ui/Resources.elm cannot be renamed."
             )}
        end
    end
  end

  def handle_event("close-rename-file-modal", _params, socket) do
    {:noreply, assign(socket, :rename_file_modal_open, false)}
  end

  def handle_event("editor-context-menu", %{"offset" => offset} = params, socket) do
    x = parse_non_negative_int(params["x"]) || 0
    y = parse_non_negative_int(params["y"]) || 0
    offset = parse_non_negative_int(offset) || 0

    {:noreply, assign(socket, :editor_context_menu, %{x: x, y: y, offset: offset})}
  end

  def handle_event("editor-context-dismiss", _params, socket) do
    {:noreply, assign(socket, :editor_context_menu, nil)}
  end

  def handle_event("editor-context-open-docs", params, socket) do
    offset = parse_non_negative_int(params["offset"]) || 0

    socket = assign(socket, :editor_context_menu, nil)

    case active_tab(socket) do
      %{content: content, rel_path: rel_path} ->
        if elm_source_file?(rel_path) do
          case EditorDocLinks.resolve(content, offset, socket.assigns.package_doc_index) do
            {:ok, %{url: url, package: package, module: mod_name}} ->
              socket =
                socket
                |> assign(:editor_docs_panel_open, true)
                |> assign(:editor_doc_package, package)
                |> assign(:editor_doc_module, mod_name)

              socket =
                case Enum.find(socket.assigns.editor_doc_packages, &(&1.package == package)) do
                  %{version: v} -> load_editor_doc_body(socket, package, v, mod_name)
                  _ -> load_editor_doc_body(socket, package, "latest", mod_name)
                end

              {:noreply, push_event(socket, "open_url", %{url: url})}

            {:error, _} ->
              {:noreply,
               put_flash(socket, :error, "Could not resolve documentation for this symbol.")}
          end
        else
          {:noreply, socket}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Open a file first.")}
    end
  end

  def handle_event("toggle-editor-docs-panel", _params, socket) do
    {:noreply, assign(socket, :editor_docs_panel_open, !socket.assigns.editor_docs_panel_open)}
  end

  def handle_event("set-editor-docs-width", %{"px" => px}, socket) do
    n =
      case Integer.parse(to_string(px)) do
        {i, _} -> i
        _ -> socket.assigns.editor_docs_col_px
      end

    n = n |> max(200) |> min(720)
    {:noreply, assign(socket, :editor_docs_col_px, n)}
  end

  def handle_event("editor-doc-package", %{"doc_pkg" => package}, socket) do
    package = package || ""

    cond do
      package == "" ->
        {:noreply,
         socket
         |> assign(:editor_doc_package, nil)
         |> assign(:editor_doc_module, "")
         |> assign(:editor_doc_html, "")}

      true ->
        row = Enum.find(socket.assigns.editor_doc_packages, &(&1.package == package))
        mod = if row && row.modules != [], do: hd(row.modules), else: ""

        socket =
          socket
          |> assign(:editor_doc_package, package)
          |> assign(:editor_doc_module, mod)

        socket =
          if row do
            load_editor_doc_body(socket, row.package, row.version, mod)
          else
            socket
          end

        {:noreply, socket}
    end
  end

  def handle_event("editor-doc-module", %{"doc_mod" => mod}, socket) do
    mod = mod || ""
    package = socket.assigns.editor_doc_package

    if package do
      row = Enum.find(socket.assigns.editor_doc_packages, &(&1.package == package))
      version = if row, do: row.version, else: "latest"

      {:noreply,
       socket
       |> assign(:editor_doc_module, mod)
       |> load_editor_doc_body(package, version, mod)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("editor-doc-search", %{"doc_q" => query}, socket) do
    {:noreply, assign(socket, :editor_doc_query, to_string(query || ""))}
  end

  def handle_event("tokenize-active-file", _params, socket) do
    case active_tab(socket) do
      nil ->
        {:noreply, put_flash(socket, :error, "No active file to tokenize.")}

      tab ->
        {:noreply,
         socket
         |> assign_tokenization(tab.content, tab.rel_path, mode: :compiler)
         |> put_flash(
           :info,
           "Tokenizer refreshed for #{editor_source_display_path(tab.rel_path)}"
         )}
    end
  end

  def handle_event("tokenize-compiler-idle", _params, socket) do
    case active_tab(socket) do
      nil ->
        {:noreply, socket}

      tab ->
        {:noreply,
         socket
         |> assign_tokenization(tab.content, tab.rel_path, mode: :compiler)}
    end
  end

  def handle_event("jump-to-diagnostic", params, socket) do
    line = parse_positive_int(params["line"])
    column = parse_positive_int(params["column"]) || 1
    index = parse_positive_int(params["index"])

    case {active_tab(socket), line} do
      {nil, _} ->
        {:noreply, put_flash(socket, :error, "Open a file first.")}

      {_, nil} ->
        {:noreply, socket}

      {_tab, line} ->
        {:noreply,
         socket
         |> assign(:active_diagnostic_index, if(index, do: index - 1, else: nil))
         |> sync_active_diagnostic_index_to_tab()
         |> push_event("token-editor-focus", %{line: line, column: column})}
    end
  end

  def handle_event("focus-next-diagnostic", _params, socket) do
    {:noreply, focus_diagnostic(socket, :next)}
  end

  def handle_event("focus-prev-diagnostic", _params, socket) do
    {:noreply, focus_diagnostic(socket, :prev)}
  end

  def handle_event("editor-state-changed", params, socket) do
    cursor_offset = parse_non_negative_int(params["cursor_offset"])
    scroll_top = parse_non_negative_number(params["scroll_top"])
    scroll_left = parse_non_negative_number(params["scroll_left"])
    tab_id = params["tab_id"]

    socket =
      update_editor_state_tab(socket, tab_id, fn tab ->
        state = tab.editor_state || %{}

        updated_state =
          state
          |> maybe_put_state(:cursor_offset, cursor_offset)
          |> maybe_put_state(:scroll_top, scroll_top)
          |> maybe_put_state(:scroll_left, scroll_left)

        %{tab | editor_state: updated_state}
      end)

    {:noreply, socket}
  end

  def handle_event("run-pebble-build", _params, socket) do
    project = socket.assigns.project

    {:noreply,
     socket
     |> assign(:pebble_build_status, :running)
     |> start_async(:run_pebble_build, fn -> PebbleToolchain.build(project.slug, []) end)}
  end

  def handle_event("run-emulator-install", _params, socket) do
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

  def handle_event("stop-emulator", _params, socket) do
    project = socket.assigns.project

    {:noreply,
     socket
     |> assign(:emulator_stop_status, :running)
     |> assign(:emulator_stop_output, nil)
     |> start_async(:stop_emulator, fn ->
       PebbleToolchain.stop_emulator(project.slug, force: true)
     end)}
  end

  def handle_event("external-emulator-control", params, socket) do
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
    project = socket.assigns.project
    emulator_target = socket.assigns.selected_emulator_target

    {:noreply,
     socket
     |> assign(:screenshot_status, :running)
     |> start_async(:capture_screenshot, fn ->
       Screenshots.capture(project.slug, emulator_target: emulator_target)
     end)}
  end

  def handle_event("wasm-screenshot-saved", %{"screenshot" => screenshot}, socket) do
    screenshots =
      socket.assigns.screenshots
      |> EmulatorFlow.upsert_screenshot(atomize_screenshot(screenshot))

    readiness = PublishFlow.publish_readiness(screenshots)

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
    token = System.unique_integer([:positive])
    lv = self()
    target_statuses = Enum.into(socket.assigns.emulator_targets, %{}, &{&1, "pending"})

    {:noreply,
     socket
     |> assign(:capture_all_status, :running)
     |> assign(:capture_all_token, token)
     |> assign(:capture_all_progress, "Starting screenshot capture...")
     |> assign(:capture_all_output, nil)
     |> assign(:capture_all_progress_lines, [])
     |> assign(:capture_all_target_statuses, target_statuses)
     |> start_async(:capture_all_screenshots, fn ->
       Screenshots.capture_all_targets(project.slug,
         workspace_root: workspace_root,
         target_type: project.target_type,
         project_name: project.name,
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

    case Screenshots.delete(project.slug, emulator_target, filename, []) do
      :ok ->
        screenshots = load_screenshots(project)
        readiness = PublishFlow.publish_readiness(screenshots)

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

    case Screenshots.delete_target(project.slug, emulator_target, []) do
      :ok ->
        screenshots = load_screenshots(project)
        readiness = PublishFlow.publish_readiness(screenshots)

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

  def handle_event("update-release-summary", %{"release_summary" => params}, socket) do
    summary = PublishFlow.merge_release_summary(socket.assigns.release_summary, params)

    {:noreply,
     socket
     |> assign(:release_summary, summary)
     |> assign(:release_summary_form, to_form(summary, as: :release_summary))}
  end

  def handle_event("save-project-settings", %{"project_settings" => params}, socket) do
    project = socket.assigns.project
    defaults = project.release_defaults || %{}
    github = project.github || %{}

    version_label = String.trim(params["version_label"] || "")
    tags = String.trim(params["tags"] || "")
    target_platforms = State.target_platforms_form_value(params["target_platforms"])
    capabilities = State.capabilities_form_value(params["capabilities"])
    github_owner = String.trim(params["github_owner"] || "")
    github_repo = String.trim(params["github_repo"] || "")
    github_branch = String.trim(params["github_branch"] || "")

    attrs = %{
      "release_defaults" =>
        defaults
        |> Map.put("version_label", version_label)
        |> Map.put("tags", tags)
        |> Map.put("target_platforms", target_platforms)
        |> Map.put("capabilities", capabilities),
      "github" =>
        github
        |> Map.put("owner", github_owner)
        |> Map.put("repo", github_repo)
        |> Map.put("branch", github_branch)
    }

    case Projects.update_project(project, attrs) do
      {:ok, updated} ->
        release_summary =
          socket.assigns.release_summary
          |> Map.put("version_label", version_label)
          |> Map.put("tags", tags)

        {:noreply,
         socket
         |> assign(:project, updated)
         |> assign(
           :project_settings_form,
           to_form(State.project_settings_form_data(updated), as: :project_settings)
         )
         |> assign(:release_summary, release_summary)
         |> assign(:release_summary_form, to_form(release_summary, as: :release_summary))
         |> put_flash(:info, "Project settings saved.")}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Could not save project settings: #{inspect(reason)}")}
    end
  end

  def handle_event("prepare-release", _params, socket) do
    project = socket.assigns.project
    workspace_root = Projects.project_workspace_path(project)
    release_summary = socket.assigns.release_summary

    socket = maybe_warn_uncommitted_prepare_release(socket, workspace_root)

    {:noreply,
     socket
     |> assign(:prepare_release_status, :running)
     |> assign(:prepare_release_output, nil)
     |> assign(:publish_status, :running)
     |> assign(:manifest_export_status, :running)
     |> assign(:release_notes_status, :running)
     |> start_async(:prepare_release, fn ->
       PublishFlow.run_prepare_release(project, workspace_root, release_summary)
     end)}
  end

  def handle_event("push-project-snapshot", _params, socket) do
    project = socket.assigns.project
    repo_config = project.github || %{}

    {:noreply,
     socket
     |> assign(:github_push_status, :running)
     |> assign(:github_push_output, nil)
     |> start_async(:push_project_snapshot, fn ->
       GitHubPush.push_project_snapshot(project, repo_config)
     end)}
  end

  def handle_event("update-publish-submit-options", %{"publish_submit" => params}, socket) do
    options = merge_publish_submit_options(socket.assigns.publish_submit_options, params)
    {:noreply, assign(socket, :publish_submit_options, options)}
  end

  def handle_event("submit-publish-release", _params, socket) do
    project = socket.assigns.project
    app_root = socket.assigns.publish_app_root
    options = socket.assigns.publish_submit_options

    if is_binary(app_root) and app_root != "" do
      publish_notes =
        PublishFlow.release_notes_markdown(
          socket.assigns.publish_checks,
          socket.assigns.publish_readiness,
          socket.assigns.publish_artifact_path,
          project.slug,
          socket.assigns.release_summary
        )

      submit_opts = [
        app_root: app_root,
        release_notes: publish_notes,
        is_published: options["is_published"] == true,
        all_platforms: options["all_platforms"] == true
      ]

      {:noreply,
       socket
       |> assign(:publish_submit_status, :running)
       |> assign(:publish_submit_output, nil)
       |> start_async(:submit_publish_release, fn ->
         PebbleToolchain.publish(project.slug, submit_opts)
       end)}
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         "No publish app root available yet. Run Prepare Release first."
       )}
    end
  end

  def handle_event("resolve-publish-check", %{"check-id" => "screenshot_coverage"}, socket) do
    project = socket.assigns.project
    workspace_root = Projects.project_workspace_path(project)
    package_path = socket.assigns.publish_artifact_path
    token = System.unique_integer([:positive])
    lv = self()
    target_statuses = Enum.into(socket.assigns.emulator_targets, %{}, &{&1, "pending"})

    {:noreply,
     socket
     |> put_flash(:info, "Capturing screenshots for all emulator targets...")
     |> assign(:capture_all_status, :running)
     |> assign(:capture_all_token, token)
     |> assign(:capture_all_progress, "Starting screenshot capture...")
     |> assign(:capture_all_output, nil)
     |> assign(:capture_all_progress_lines, [])
     |> assign(:capture_all_target_statuses, target_statuses)
     |> start_async(:capture_all_screenshots, fn ->
       Screenshots.capture_all_targets(project.slug,
         workspace_root: workspace_root,
         target_type: project.target_type,
         project_name: project.name,
         package_path: package_path,
         close_emulator_afterwards: true,
         progress: fn msg -> send(lv, {:capture_all_progress, token, msg}) end
       )
     end)}
  end

  def handle_event("resolve-publish-check", %{"check-id" => "artifact_exists"}, socket) do
    project = socket.assigns.project
    workspace_root = Projects.project_workspace_path(project)

    {:noreply,
     socket
     |> assign(:publish_status, :running)
     |> start_async(:prepare_publish_artifact, fn ->
       PebbleToolchain.package(project.slug,
         workspace_root: workspace_root,
         target_type: project.target_type,
         project_name: project.name
       )
     end)}
  end

  def handle_event("resolve-publish-check", %{"check-id" => check_id}, socket) do
    {:noreply, put_flash(socket, :info, PublishFlow.quick_fix_message(check_id))}
  end

  def handle_event("prepare-publish-artifact", _params, socket) do
    project = socket.assigns.project
    workspace_root = Projects.project_workspace_path(project)

    {:noreply,
     socket
     |> assign(:publish_status, :running)
     |> start_async(:prepare_publish_artifact, fn ->
       PebbleToolchain.package(project.slug,
         workspace_root: workspace_root,
         target_type: project.target_type,
         project_name: project.name
       )
     end)}
  end

  def handle_event("export-publish-manifest", _params, socket) do
    project = socket.assigns.project
    artifact_path = socket.assigns.publish_artifact_path
    screenshot_groups = socket.assigns.screenshot_groups
    required_targets = ToolchainPresenter.emulator_targets()
    readiness = socket.assigns.publish_readiness

    {:noreply,
     socket
     |> assign(:manifest_export_status, :running)
     |> start_async(:export_publish_manifest, fn ->
       PublishManifest.export(project.slug,
         artifact_path: artifact_path,
         screenshot_groups: screenshot_groups,
         required_targets: required_targets,
         readiness: readiness
       )
     end)}
  end

  def handle_event("export-release-notes", _params, socket) do
    project = socket.assigns.project
    publish_checks = socket.assigns.publish_checks
    publish_readiness = socket.assigns.publish_readiness
    publish_artifact_path = socket.assigns.publish_artifact_path
    project_slug = project.slug
    release_summary = socket.assigns.release_summary

    {:noreply,
     socket
     |> assign(:release_notes_status, :running)
     |> start_async(:export_release_notes, fn ->
       markdown =
         PublishFlow.release_notes_markdown(
           publish_checks,
           publish_readiness,
           publish_artifact_path,
           project_slug,
           release_summary
         )

       PublishManifest.export_release_notes(project_slug, markdown)
     end)}
  end

  def handle_event("set-emulator-target", %{"emulator" => params}, socket) do
    project =
      socket.assigns.project
      |> persist_project_emulator_target(Map.get(params, "target"))
      |> persist_project_emulator_mode(Map.get(params, "mode"))

    target = project_emulator_target(project)
    mode = project_emulator_mode(project)

    {:noreply,
     socket
     |> assign(:project, project)
     |> assign(:selected_emulator_target, target)
     |> assign(:emulator_mode, mode)
     |> assign(:emulator_form, to_form(%{"target" => target, "mode" => mode}, as: :emulator))
     |> check_emulator_installation()}
  end

  def handle_event("debugger-start", _params, socket) do
    case socket.assigns.project do
      nil ->
        {:noreply, socket}

      project ->
        {:ok, _state} =
          Ide.Debugger.start_session(project.slug, %{
            watch_profile_id: project_debugger_watch_profile_id(project)
          })

        socket =
          socket
          |> DebuggerSupport.refresh()
          |> warm_debugger_compile_context(project)

        {socket, message} = bootstrap_debugger_preview(socket, project)
        apply_project_auto_fire_settings(project)

        socket =
          socket
          |> DebuggerSupport.refresh()
          |> maybe_schedule_debugger_auto_fire_refresh()

        socket =
          if debugger_session_active?(socket) do
            schedule_compiler_check(socket)
          else
            socket
          end

        {:noreply, put_flash(socket, :info, message)}
    end
  end

  def handle_event("debugger-toggle-advanced", _params, socket) do
    {:noreply,
     assign(
       socket,
       :debugger_advanced_debug_tools,
       !socket.assigns.debugger_advanced_debug_tools
     )}
  end

  def handle_event("debugger-set-timeline-mode", %{"mode" => mode}, socket) do
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
        {:ok, _state} = Ide.Debugger.set_auto_fire(project.slug, attrs)

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
        {:ok, _state} = Ide.Debugger.set_subscription_enabled(project.slug, attrs)

        {:noreply,
         socket
         |> assign(:project, project)
         |> DebuggerSupport.refresh()
         |> maybe_schedule_debugger_auto_fire_refresh()}
    end
  end

  def handle_event("debugger-save-configuration", %{"configuration" => values}, socket)
      when is_map(values) do
    case socket.assigns.project do
      nil ->
        {:noreply, socket}

      project ->
        project = persist_project_debugger_configuration_values(project, values)
        {:ok, _state} = Ide.Debugger.save_configuration(project.slug, values)

        {:noreply,
         socket
         |> assign(:project, project)
         |> DebuggerSupport.refresh()
         |> DebuggerSupport.jump_latest()
         |> put_flash(:info, "Saved companion configuration.")}
    end
  end

  def handle_event("debugger-save-configuration", _params, socket), do: {:noreply, socket}

  def handle_event("debugger-reset-configuration", _params, socket) do
    case socket.assigns.project do
      nil ->
        {:noreply, socket}

      project ->
        project = reset_project_debugger_configuration_values(project)
        {:ok, _state} = Ide.Debugger.reload_configuration(project.slug)

        {:noreply,
         socket
         |> assign(:project, project)
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
          Ide.Debugger.set_watch_profile(project.slug, %{
            watch_profile_id: selected_watch_profile_id
          })

        {:noreply,
         socket
         |> assign(:project, project)
         |> DebuggerSupport.refresh()
         |> put_flash(:info, "Debugger watch profile set to #{selected_watch_profile_id}.")}
    end
  end

  def handle_event("debugger-tick", _params, socket) do
    case socket.assigns.project do
      nil ->
        {:noreply, socket}

      project ->
        {:ok, _state} = Ide.Debugger.tick(project.slug, %{target: "watch"})

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
          Ide.Debugger.start_auto_tick(project.slug, %{
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
        {:ok, _state} = Ide.Debugger.stop_auto_tick(project.slug)
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

  def handle_event("debugger-submit-trigger", %{"debugger_trigger" => params}, socket) do
    case socket.assigns.project do
      nil ->
        {:noreply, close_debugger_trigger_modal(socket)}

      project ->
        trigger = Map.get(params, "trigger")

        attrs = %{
          trigger: trigger,
          target: Map.get(params, "target"),
          message: debugger_trigger_submit_message(params)
        }

        {:ok, _state} = Ide.Debugger.inject_trigger(project.slug, attrs)

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

        {:ok, _state} = Ide.Debugger.inject_trigger(project.slug, attrs)

        {:noreply,
         socket
         |> DebuggerSupport.refresh()
         |> DebuggerSupport.jump_latest()
         |> put_flash(:info, "Injected trigger #{trigger}.")}
    end
  end

  def handle_event("debugger-continue-from-cursor", _params, socket) do
    case socket.assigns.project do
      nil ->
        {:noreply, socket}

      project ->
        {:ok, _state} =
          Ide.Debugger.continue_from_snapshot(project.slug, %{
            cursor_seq: socket.assigns[:debugger_cursor_seq]
          })

        {:noreply,
         socket
         |> DebuggerSupport.refresh()
         |> put_flash(:info, "Continued live runtime from selected cursor snapshot.")}
    end
  end

  def handle_event("debugger-set-cursor", %{"debugger_timeline" => timeline}, socket)
      when is_map(timeline) do
    seq = Map.get(timeline, "seq") || Map.get(timeline, "range_seq")
    {:noreply, DebuggerSupport.set_cursor_seq(socket, seq)}
  end

  def handle_event("debugger-set-compare-baseline", %{"debugger_compare" => compare}, socket)
      when is_map(compare) do
    {:noreply, DebuggerSupport.set_compare_form(socket, compare)}
  end

  def handle_event("debugger-select-event", %{"seq" => seq}, socket) do
    {:noreply, DebuggerSupport.set_cursor_seq(socket, seq)}
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

  def handle_event("debugger-set-timeline-kind", %{"kind" => kind}, socket) do
    {:noreply, DebuggerSupport.set_timeline_kind(socket, kind)}
  end

  def handle_event("debugger-set-timeline-limit", %{"timeline" => %{"limit" => limit}}, socket) do
    {:noreply, DebuggerSupport.set_timeline_limit(socket, limit)}
  end

  def handle_event("debugger-set-timeline-search", %{"timeline" => %{"query" => query}}, socket) do
    {:noreply, DebuggerSupport.set_timeline_query(socket, query)}
  end

  def handle_event("debugger-keydown", %{"key" => "j"}, socket) do
    {:noreply, DebuggerSupport.step_back(socket)}
  end

  def handle_event("debugger-keydown", %{"key" => "k"}, socket) do
    {:noreply, DebuggerSupport.step_forward(socket)}
  end

  def handle_event(
        "debugger-set-filters",
        %{"debugger_filter" => %{"types" => types_text, "since_seq" => since_seq_text}},
        socket
      ) do
    {:noreply, DebuggerSupport.apply_filter_inputs(socket, types_text, since_seq_text)}
  end

  def handle_event("debugger-filter-type", %{"type" => type}, socket) do
    {:noreply, DebuggerSupport.apply_type_filter(socket, type)}
  end

  def handle_event("debugger-replay-recent", %{"debugger_replay" => replay}, socket)
      when is_map(replay) do
    socket = DebuggerSupport.replay_recent(socket, replay)
    {:noreply, put_flash(socket, :info, "Replayed recent debugger messages.")}
  end

  def handle_event("debugger-replay-change", %{"debugger_replay" => replay}, socket)
      when is_map(replay) do
    {:noreply, DebuggerSupport.set_replay_form(socket, replay)}
  end

  def handle_event("debugger-replay-refresh-preview", _params, socket) do
    params = DebuggerSupport.replay_form_params(socket)
    {:noreply, DebuggerSupport.set_replay_form(socket, params)}
  end

  def handle_event("debugger-use-preview-baseline", _params, socket) do
    {:noreply, DebuggerSupport.use_preview_as_compare_baseline(socket)}
  end

  def handle_event("debugger-export-trace", params, socket) do
    export_params =
      case params do
        %{"debugger_export" => payload} when is_map(payload) -> payload
        _ -> %{}
      end

    case socket.assigns.project do
      nil ->
        {:noreply, socket}

      project ->
        export_opts = DebuggerSupport.export_trace_opts(socket, export_params)
        compare_cursor_seq = Keyword.get(export_opts, :compare_cursor_seq)
        baseline_cursor_seq = Keyword.get(export_opts, :baseline_cursor_seq)
        {:ok, export} = Ide.Debugger.export_trace(project.slug, export_opts)

        {:noreply,
         socket
         |> DebuggerSupport.set_export_form(export_params)
         |> assign(:debugger_trace_export, export)
         |> assign(
           :debugger_trace_export_context,
           %{
             compare_cursor_seq: compare_cursor_seq,
             baseline_cursor_seq: baseline_cursor_seq
           }
         )
         |> put_flash(
           :info,
           "Debugger trace export ready (#{export.byte_size} bytes, sha256 #{export.sha256})."
         )}
    end
  end

  def handle_event("debugger-import-trace", params, socket) do
    json =
      case params do
        %{"debugger_import" => %{"json" => j}} when is_binary(j) -> String.trim(j)
        _ -> ""
      end

    case socket.assigns.project do
      nil ->
        {:noreply, socket}

      project ->
        cond do
          json == "" ->
            {:noreply, put_flash(socket, :error, "Paste trace JSON before importing.")}

          true ->
            case Ide.Debugger.import_trace(project.slug, json) do
              {:ok, _state} ->
                {:noreply,
                 socket
                 |> assign(:debugger_import_form, DebuggerSupport.import_trace_form())
                 |> assign(:debugger_trace_export_context, nil)
                 |> DebuggerSupport.refresh()
                 |> put_flash(:info, "Debugger trace imported; timeline restored from export.")}

              {:error, reason} ->
                {:noreply, put_flash(socket, :error, debugger_import_error(reason))}
            end
        end
    end
  end

  defp update_tab_by_id(socket, tab_id, updater)
       when is_binary(tab_id) and is_function(updater, 1) do
    tabs =
      Enum.map(socket.assigns.tabs, fn tab ->
        if tab.id == tab_id do
          updater.(tab)
        else
          tab
        end
      end)

    assign(socket, :tabs, tabs)
  end

  defp refresh_tab_read_only(%{source_root: source_root, rel_path: rel_path} = tab)
       when is_binary(source_root) and is_binary(rel_path) do
    %{
      tab
      | read_only:
          tab[:read_only] || ResourceStore.read_only_generated_module?(source_root, rel_path)
    }
  end

  defp refresh_tab_read_only(tab), do: tab

  @impl true
  @spec handle_async(term(), term(), term()) :: term()
  def handle_async(:run_check, result, socket),
    do: BuildFlow.handle_async(:run_check, result, socket)

  def handle_async(:open_file, {:ok, {{:ok, contents}, token, source_root, rel_path}}, socket) do
    if socket.assigns.file_open_token == token do
      editor_state = default_editor_state()

      tab = %{
        id: tab_id(source_root, rel_path),
        source_root: source_root,
        rel_path: rel_path,
        content: contents,
        dirty: false,
        read_only: ResourceStore.read_only_generated_module?(source_root, rel_path),
        editor_state: editor_state
      }

      tabs =
        socket.assigns.tabs
        |> Enum.reject(&(&1.id == tab.id))
        |> Kernel.++([tab])

      {:noreply,
       socket
       |> assign(:opening_file_id, nil)
       |> assign(:opening_file_label, nil)
       |> assign(:file_open_token, nil)
       |> assign(tabs: tabs, active_tab_id: tab.id)
       |> assign(:active_diagnostic_index, editor_state.active_diagnostic_index)
       |> assign_tokenization(contents, rel_path, mode: :compiler)
       |> restore_editor_state(editor_state)}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:open_file, {:ok, {{:error, reason}, token, _source_root, _rel_path}}, socket) do
    if socket.assigns.file_open_token == token do
      {:noreply,
       socket
       |> assign(:opening_file_id, nil)
       |> assign(:opening_file_label, nil)
       |> assign(:file_open_token, nil)
       |> put_flash(:error, "Could not open file: #{inspect(reason)}")}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:open_file, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:opening_file_id, nil)
     |> assign(:opening_file_label, nil)
     |> assign(:file_open_token, nil)
     |> put_flash(:error, "Failed to open file: #{inspect(reason)}")}
  end

  def handle_async(:refresh_editor_dependency_usage, {:ok, {payload, token}}, socket) do
    if socket.assigns[:editor_deps_usage_refresh_token] == token and
         Map.get(payload, :dependencies_available?, true) do
      {:noreply,
       socket
       |> assign(:editor_deps_usage_refresh_token, nil)
       |> assign(:project_elm_direct, payload.direct)
       |> assign(:project_elm_indirect, payload.indirect)}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:refresh_editor_dependency_usage, {:exit, _reason}, socket) do
    {:noreply, socket}
  end

  def handle_async(:refresh_editor_dependencies, {:ok, {payload, token}}, socket) do
    if socket.assigns[:editor_deps_docs_refresh_token] == token do
      socket =
        socket
        |> assign(:editor_deps_docs_refresh_token, nil)
        |> assign(:package_doc_index, payload.package_doc_index)
        |> apply_doc_catalog_rows(payload.editor_doc_packages)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:refresh_editor_dependencies, {:exit, _reason}, socket) do
    {:noreply, socket}
  end

  def handle_async(:editor_check, {:ok, {{:ok, result}, token, source_root, rel_path}}, socket) do
    if socket.assigns.editor_check_token == token do
      {:noreply,
       socket
       |> assign(:editor_check_status, result.status)
       |> assign(:editor_check_token, nil)
       |> assign(:editor_check_source_root, source_root)
       |> assign(:editor_check_rel_path, rel_path)
       |> assign(:editor_check_diagnostics, result.diagnostics || [])
       |> assign(:editor_check_output, result.output)
       |> push_editor_check_lint_diagnostics(source_root, rel_path, result.diagnostics || [])}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:editor_check, {:ok, {{:error, reason}, token, source_root, rel_path}}, socket) do
    if socket.assigns.editor_check_token == token do
      diagnostics = [
        %{
          severity: "error",
          source: "editor-check",
          message: "Could not check saved file: #{inspect(reason)}",
          file: nil,
          line: nil,
          column: nil
        }
      ]

      {:noreply,
       socket
       |> assign(:editor_check_status, :error)
       |> assign(:editor_check_token, nil)
       |> assign(:editor_check_source_root, source_root)
       |> assign(:editor_check_rel_path, rel_path)
       |> assign(:editor_check_diagnostics, diagnostics)
       |> assign(:editor_check_output, inspect(reason))
       |> push_editor_check_lint_diagnostics(source_root, rel_path, diagnostics)}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:editor_check, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:editor_check_status, :error)
     |> assign(:editor_check_token, nil)
     |> assign(:editor_check_diagnostics, [
       %{
         severity: "error",
         source: "editor-check",
         message: "Editor check task exited: #{inspect(reason)}",
         file: nil,
         line: nil,
         column: nil
       }
     ])
     |> assign(:editor_check_output, inspect(reason))}
  end

  def handle_async(:run_build, result, socket),
    do: BuildFlow.handle_async(:run_build, result, socket)

  def handle_async(:run_compile, result, socket),
    do: BuildFlow.handle_async(:run_compile, result, socket)

  def handle_async(:run_manifest, result, socket),
    do: BuildFlow.handle_async(:run_manifest, result, socket)

  def handle_async(
        :format_file,
        {:ok, {:ok, %{tab: tab, result: result, write_result: :ok}}},
        socket
      ) do
    socket =
      socket
      |> assign(:format_status, :ok)
      |> assign(:format_output, render_format_output(result))
      |> update_tab(fn active ->
        if active.id == tab.id do
          %{active | content: result.formatted_source, dirty: false}
        else
          active
        end
      end)

    socket =
      if socket.assigns.active_tab_id == tab.id do
        cursor = formatted_cursor_offset(socket, result.formatted_source)

        edit_patch =
          EditPatch.from_contents(
            tab.content,
            result.formatted_source,
            cursor,
            cursor
          )

        socket
        |> assign_tokenization(result.formatted_source, tab.rel_path, mode: :compiler)
        |> push_event("token-editor-apply-edit", edit_patch)
      else
        socket
      end

    disp = editor_source_display_path(tab.rel_path)

    flash_message =
      if result.changed?,
        do: "Formatted #{disp}.",
        else: "Already formatted: #{disp}."

    {:noreply, put_flash(socket, :info, flash_message)}
  end

  def handle_async(
        :format_file,
        {:ok, {:ok, %{tab: _tab, write_result: {:error, reason}}}},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:format_status, :error)
     |> assign(:format_output, "Format completed but save failed: #{inspect(reason)}")}
  end

  def handle_async(:format_file, {:ok, {:error, %{reason: reason}}}, socket) do
    {:noreply,
     socket
     |> assign(:format_status, :error)
     |> assign(:format_output, render_format_error(reason))}
  end

  def handle_async(:format_file, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:format_status, :error)
     |> assign(:format_output, render_format_error(reason))}
  end

  def handle_async(:format_file, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:format_status, :error)
     |> assign(:format_output, "Format task exited: #{inspect(reason)}")}
  end

  def handle_async(:run_pebble_build, {:ok, {:ok, result}}, socket) do
    {:noreply,
     socket
     |> assign(:pebble_build_status, result.status)
     |> assign(:pebble_build_output, ToolchainPresenter.render_toolchain_output(result))}
  end

  def handle_async(:run_pebble_build, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:pebble_build_status, :error)
     |> assign(:pebble_build_output, "Build failed before execution: #{inspect(reason)}")}
  end

  def handle_async(:run_pebble_build, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:pebble_build_status, :error)
     |> assign(:pebble_build_output, "Build task exited: #{inspect(reason)}")}
  end

  def handle_async(:check_emulator_installation, {:ok, status}, socket) do
    {:noreply, assign(socket, :emulator_installation_status, status)}
  end

  def handle_async(:check_emulator_installation, {:exit, reason}, socket) do
    {:noreply,
     assign(socket, :emulator_installation_status, %{
       status: :error,
       components: [],
       missing: [],
       installable: false,
       error: "Emulator installation check exited: #{inspect(reason)}"
     })}
  end

  def handle_async(:install_emulator_dependencies, {:ok, {:ok, result}}, socket) do
    {:noreply,
     socket
     |> assign(:emulator_dependency_install_status, result.after.status)
     |> assign(:emulator_dependency_install_output, result.output)
     |> assign(:emulator_installation_status, result.after)}
  end

  def handle_async(:install_emulator_dependencies, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:emulator_dependency_install_status, :error)
     |> assign(
       :emulator_dependency_install_output,
       "Dependency install failed: #{inspect(reason)}"
     )
     |> check_emulator_installation()}
  end

  def handle_async(:install_emulator_dependencies, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:emulator_dependency_install_status, :error)
     |> assign(
       :emulator_dependency_install_output,
       "Dependency install task exited: #{inspect(reason)}"
     )
     |> check_emulator_installation()}
  end

  def handle_async(:run_emulator_install, {:ok, {:ok, result}}, socket) do
    socket =
      if is_binary(result[:artifact_path]) do
        assign(socket, :publish_artifact_path, result.artifact_path)
      else
        socket
      end

    {:noreply,
     socket
     |> assign(:pebble_install_status, result.status)
     |> assign(:pebble_install_output, ToolchainPresenter.render_toolchain_output(result))}
  end

  def handle_async(:run_emulator_install, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:pebble_install_status, :error)
     |> assign(:pebble_install_output, emulator_install_error_message(reason))}
  end

  def handle_async(:run_emulator_install, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:pebble_install_status, :error)
     |> assign(:pebble_install_output, "Emulator install task exited: #{inspect(reason)}")}
  end

  def handle_async(:stop_emulator, {:ok, {:ok, result}}, socket) do
    {:noreply,
     socket
     |> assign(:emulator_stop_status, result.status)
     |> assign(:emulator_stop_output, ToolchainPresenter.render_toolchain_output(result))}
  end

  def handle_async(:stop_emulator, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:emulator_stop_status, :error)
     |> assign(:emulator_stop_output, "Could not stop emulator: #{inspect(reason)}")}
  end

  def handle_async(:stop_emulator, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:emulator_stop_status, :error)
     |> assign(:emulator_stop_output, "Emulator stop task exited: #{inspect(reason)}")}
  end

  def handle_async(:external_emulator_control, {:ok, {:ok, result}}, socket) do
    {:noreply,
     socket
     |> assign(:emulator_stop_status, result.status)
     |> assign(:emulator_stop_output, ToolchainPresenter.render_toolchain_output(result))}
  end

  def handle_async(:external_emulator_control, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:emulator_stop_status, :error)
     |> assign(:emulator_stop_output, "External emulator control failed: #{inspect(reason)}")}
  end

  def handle_async(:external_emulator_control, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:emulator_stop_status, :error)
     |> assign(:emulator_stop_output, "External emulator control task exited: #{inspect(reason)}")}
  end

  def handle_async(:capture_screenshot, {:ok, {:ok, result}}, socket) do
    screenshots = load_screenshots(socket.assigns.project)
    readiness = PublishFlow.publish_readiness(screenshots)

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

  def handle_async(:capture_screenshot, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:screenshot_status, :error)
     |> assign(:screenshot_output, "Screenshot failed before execution: #{inspect(reason)}")}
  end

  def handle_async(:capture_screenshot, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:screenshot_status, :error)
     |> assign(:screenshot_output, "Screenshot task exited: #{inspect(reason)}")}
  end

  def handle_async(:capture_all_screenshots, {:ok, {:ok, result}}, socket) do
    screenshots = load_screenshots(socket.assigns.project)
    readiness = PublishFlow.publish_readiness(screenshots)

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

  def handle_async(:capture_all_screenshots, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:capture_all_status, :error)
     |> assign(:capture_all_progress, nil)
     |> assign(:capture_all_output, "Capture-all failed: #{inspect(reason)}")}
  end

  def handle_async(:capture_all_screenshots, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:capture_all_status, :error)
     |> assign(:capture_all_progress, nil)
     |> assign(:capture_all_output, "Capture-all task exited: #{inspect(reason)}")}
  end

  def handle_async(:prepare_release, {:ok, {:ok, result}}, socket) do
    warnings =
      PublishFlow.publish_warnings(result.project, result.readiness, result.release_summary)

    summary = PublishFlow.publish_summary(result.checks, warnings, result.readiness)

    {:noreply,
     socket
     |> assign(:prepare_release_status, :ok)
     |> assign(:prepare_release_output, result.output)
     |> assign(:publish_status, result.validation_status)
     |> assign(:publish_artifact_path, result.artifact_path)
     |> assign(:publish_app_root, result.app_root)
     |> assign(:publish_readiness, result.readiness)
     |> assign(:publish_checks, result.checks)
     |> assign(:publish_warnings, warnings)
     |> assign(:publish_summary, summary)
     |> assign(
       :publish_type_guidance,
       PublishFlow.publish_type_guidance(result.project, result.readiness)
     )
     |> assign(:manifest_export_status, result.manifest_status)
     |> assign(:manifest_export_path, result.manifest_path)
     |> assign(:manifest_export_output, result.manifest_output)
     |> assign(:release_notes_status, result.release_notes_status)
     |> assign(:release_notes_path, result.release_notes_path)
     |> assign(:release_notes_output, result.release_notes_output)
     |> assign(
       :publish_metrics,
       PublishFlow.update_publish_metrics(socket.assigns.publish_metrics, result)
     )}
  end

  def handle_async(:prepare_release, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:prepare_release_status, :error)
     |> assign(:publish_status, :error)
     |> assign(:manifest_export_status, :error)
     |> assign(:release_notes_status, :error)
     |> assign(:prepare_release_output, "Prepare release failed: #{inspect(reason)}")}
  end

  def handle_async(:prepare_release, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:prepare_release_status, :error)
     |> assign(:publish_status, :error)
     |> assign(:manifest_export_status, :error)
     |> assign(:release_notes_status, :error)
     |> assign(:prepare_release_output, "Prepare release task exited: #{inspect(reason)}")}
  end

  def handle_async(:prepare_publish_artifact, {:ok, {:ok, result}}, socket) do
    screenshots = load_screenshots(socket.assigns.project)

    readiness = PublishFlow.publish_readiness(screenshots)

    publish_checks =
      case PublishReadiness.validate(
             artifact_path: result.artifact_path,
             required_targets: ToolchainPresenter.emulator_targets(),
             readiness: readiness,
             app_root: result.app_root,
             project_slug: socket.assigns.project.slug
           ) do
        {:ok, validation} ->
          validation.checks

        {:error, reason} ->
          [
            %{
              id: "validation_error",
              label: "Publish validation",
              status: :error,
              message: inspect(reason)
            }
          ]
      end

    warnings =
      PublishFlow.publish_warnings(
        socket.assigns.project,
        readiness,
        socket.assigns.release_summary
      )

    {:noreply,
     socket
     |> assign(:publish_status, result.status)
     |> assign(:publish_artifact_path, result.artifact_path)
     |> assign(:publish_app_root, result.app_root)
     |> assign(:publish_readiness, readiness)
     |> assign(:publish_checks, publish_checks)
     |> assign(:publish_warnings, warnings)
     |> assign(:publish_summary, PublishFlow.publish_summary(publish_checks, warnings, readiness))
     |> assign(
       :publish_type_guidance,
       PublishFlow.publish_type_guidance(socket.assigns.project, readiness)
     )
     |> assign(:publish_output, ToolchainPresenter.render_publish_output(result))}
  end

  def handle_async(:submit_publish_release, {:ok, {:ok, result}}, socket) do
    submitted_release_summary = socket.assigns.release_summary
    next_release_summary = PublishFlow.bump_release_summary(submitted_release_summary)
    submitted_version = String.trim(submitted_release_summary["version_label"] || "")
    next_version = String.trim(next_release_summary["version_label"] || "")

    project =
      persist_project_publish_metadata(
        socket.assigns.project,
        submitted_release_summary,
        next_release_summary
      )

    socket =
      socket
      |> assign(:project, project)
      |> assign(
        :project_settings_form,
        to_form(State.project_settings_form_data(project), as: :project_settings)
      )
      |> assign(:release_summary, next_release_summary)
      |> assign(:release_summary_form, to_form(next_release_summary, as: :release_summary))
      |> assign(:publish_submit_status, result.status)
      |> assign(:publish_submit_output, ToolchainPresenter.render_toolchain_output(result))

    socket =
      if submitted_version != "" and submitted_version == next_version do
        put_flash(socket, :info, "Version was not auto-incremented (not valid semantic version).")
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_async(:submit_publish_release, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:publish_submit_status, :error)
     |> assign(:publish_submit_output, "Store publish failed: #{inspect(reason)}")}
  end

  def handle_async(:submit_publish_release, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:publish_submit_status, :error)
     |> assign(:publish_submit_output, "Store publish task exited: #{inspect(reason)}")}
  end

  def handle_async(:push_project_snapshot, {:ok, {:ok, result}}, socket) do
    {:noreply,
     socket
     |> assign(:github_push_status, :ok)
     |> assign(
       :github_push_output,
       "Pushed #{result.owner}/#{result.repo}@#{result.branch}\ncommit: #{result.commit_sha}\nurl: #{result.remote_url}"
     )}
  end

  def handle_async(:push_project_snapshot, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:github_push_status, :error)
     |> assign(:github_push_output, "Push failed: #{format_github_push_error(reason)}")}
  end

  def handle_async(:push_project_snapshot, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:github_push_status, :error)
     |> assign(:github_push_output, "Push task exited: #{inspect(reason)}")}
  end

  def handle_async(:prepare_publish_artifact, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:publish_status, :error)
     |> assign(:publish_checks, [
       %{id: "publish_error", label: "Publish prep", status: :error, message: inspect(reason)}
     ])
     |> assign(:publish_output, "Publish artifact generation failed: #{inspect(reason)}")}
  end

  def handle_async(:prepare_publish_artifact, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:publish_status, :error)
     |> assign(:publish_checks, [
       %{id: "publish_exit", label: "Publish prep", status: :error, message: inspect(reason)}
     ])
     |> assign(:publish_output, "Publish artifact task exited: #{inspect(reason)}")}
  end

  def handle_async(:export_publish_manifest, {:ok, {:ok, result}}, socket) do
    {:noreply,
     socket
     |> assign(:manifest_export_status, :ok)
     |> assign(:manifest_export_path, result.path)
     |> assign(:manifest_export_output, ToolchainPresenter.render_manifest_export_output(result))}
  end

  def handle_async(:export_publish_manifest, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:manifest_export_status, :error)
     |> assign(:manifest_export_output, "Manifest export failed: #{inspect(reason)}")}
  end

  def handle_async(:export_publish_manifest, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:manifest_export_status, :error)
     |> assign(:manifest_export_output, "Manifest export task exited: #{inspect(reason)}")}
  end

  def handle_async(:export_release_notes, {:ok, {:ok, result}}, socket) do
    {:noreply,
     socket
     |> assign(:release_notes_status, :ok)
     |> assign(:release_notes_path, result.path)
     |> assign(:release_notes_output, "Release notes exported to #{result.path}")}
  end

  def handle_async(:export_release_notes, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:release_notes_status, :error)
     |> assign(:release_notes_output, "Release notes export failed: #{inspect(reason)}")}
  end

  def handle_async(:export_release_notes, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:release_notes_status, :error)
     |> assign(:release_notes_output, "Release notes export task exited: #{inspect(reason)}")}
  end

  def handle_async(:packages_search, {:ok, {{:ok, result}, token}}, socket) do
    if socket.assigns.packages_search_token == token do
      {:noreply,
       socket
       |> assign(:packages_search_busy, false)
       |> assign(:packages_search_progress, nil)
       |> assign(:packages_query, result.query)
       |> assign(:packages_search_results, result.packages)
       |> assign(:packages_search_total, result.total)
       |> PackagesFlow.maybe_select_first_package()}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:packages_search, {:ok, {{:error, reason}, token}}, socket) do
    if socket.assigns.packages_search_token == token do
      {:noreply,
       socket
       |> assign(:packages_search_busy, false)
       |> assign(:packages_search_progress, nil)
       |> put_flash(:error, "Package search failed: #{inspect(reason)}")}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:packages_search, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:packages_search_busy, false)
     |> assign(:packages_search_progress, nil)
     |> put_flash(:error, "Package search interrupted: #{inspect(reason)}")}
  end

  def handle_async(:packages_inspect, {:ok, {:ok, p}}, socket) do
    socket =
      socket
      |> assign(:packages_inspect_loading, nil)
      |> assign(:packages_selected, p.package)
      |> assign(:packages_details, p.details)
      |> assign(:packages_versions, p.versions)
      |> assign(:packages_readme, p.readme)
      |> PackagesFlow.refresh_preview()

    {:noreply, socket}
  end

  def handle_async(:packages_inspect, {:ok, {:error, package, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:packages_inspect_loading, nil)
     |> assign(:packages_selected, package)
     |> assign(:packages_details, nil)
     |> assign(:packages_versions, [])
     |> assign(:packages_readme, nil)
     |> assign(:packages_preview, nil)
     |> put_flash(:error, "Could not load package details: #{inspect(reason)}")}
  end

  def handle_async(:packages_inspect, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:packages_inspect_loading, nil)
     |> put_flash(:error, "Package inspection interrupted: #{inspect(reason)}")}
  end

  defp maybe_regenerate_phone_preferences_after_save(
         socket,
         %{source_root: "phone", rel_path: rel_path}
       )
       when is_binary(rel_path) do
    if String.ends_with?(rel_path, ".elm") and
         rel_path != PebblePreferences.generated_bridge_rel_path() do
      :ok = Projects.ensure_generated_phone_preferences(socket.assigns.project)

      socket
      |> refresh_open_generated_preferences_tab()
      |> refresh_tree()
    else
      socket
    end
  end

  defp maybe_regenerate_phone_preferences_after_save(socket, _tab), do: socket

  defp refresh_open_generated_preferences_tab(socket) do
    rel_path = PebblePreferences.generated_bridge_rel_path()

    case Projects.read_source_file(socket.assigns.project, "phone", rel_path) do
      {:ok, content} ->
        tabs =
          Enum.map(socket.assigns.tabs, fn
            %{source_root: "phone", rel_path: ^rel_path} = tab ->
              %{tab | content: content, dirty: false, read_only: true}

            tab ->
              tab
          end)

        assign(socket, :tabs, tabs)

      _ ->
        socket
    end
  end

  @impl true
  @spec handle_info(term(), term()) :: term()
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

  @impl true
  def handle_info({:packages_search_progress, token, msg}, socket) do
    if socket.assigns.packages_search_token == token do
      {:noreply,
       assign(socket, :packages_search_progress, PackagesFlow.search_progress_label(msg))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  @spec render(term()) :: term()
  def render(assigns) do
    ~H"""
    <div
      id="workspace-live-root"
      class="flex h-screen w-full max-w-none flex-col p-4"
      phx-hook="DebuggerShortcuts"
      data-pane={Atom.to_string(@pane)}
    >
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
          navigate={settings_path_with_return_to("/projects/#{@project.slug}/#{@pane}")}
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

  defdelegate active_tab(socket), to: EditorSupport
  defdelegate active_tab(tabs, active_tab_id), to: EditorSupport
  defdelegate read_only_tab?(tab), to: EditorSupport
  defdelegate ensure_can_modify_editor_file(tab), to: EditorSupport
  defdelegate protected_editor_source_file?(rel_path), to: EditorSupport
  defdelegate doc_catalog_source_root(socket), to: EditorSupport
  defdelegate preferred_packages_target_root(socket, project), to: EditorSupport
  defdelegate update_tab(socket, updater), to: EditorSupport
  defdelegate update_active_tab(socket, updater), to: EditorSupport
  defdelegate update_editor_state_tab(socket, tab_id, updater), to: EditorSupport
  defdelegate refresh_tree(socket), to: EditorSupport
  defdelegate refresh_editor_dependencies(socket), to: EditorSupport
  defdelegate editor_source_display_path(rel_path), to: EditorSupport
  defdelegate editor_file_tree_label(source_root, rel_path), to: EditorSupport
  defdelegate normalize_editor_src_rel_path(path), to: EditorSupport
  defdelegate settings_path_with_return_to(return_to), to: EditorSupport
  defdelegate module_name_from_rel_path(rel_path), to: EditorSupport
  defdelegate validate_new_elm_module_name(module_name), to: EditorSupport
  defdelegate new_elm_module_template(module_name), to: EditorSupport
  defdelegate maybe_initialize_forms(socket, project), to: EditorSupport
  defdelegate maybe_open_editor_default_file(socket, project, previous_pane), to: EditorSupport
  defdelegate default_editor_state(), to: EditorSupport
  defdelegate tab_id(source_root, rel_path), to: EditorSupport
  defdelegate tree_dir_key(source_root, rel_path), to: EditorSupport
  defdelegate maybe_put_kw(opts, key, value), to: EditorSupport
  defdelegate apply_text_patch(content, edit_patch), to: EditorSupport
  defdelegate identity_edit_patch(content, start_offset, end_offset), to: EditorSupport
  defdelegate semantic_edit_ops_enabled?(), to: EditorSupport
  defdelegate render_format_output(result), to: EditorSupport
  defdelegate formatted_cursor_offset(socket, formatted_source), to: EditorSupport
  defdelegate render_format_error(reason), to: EditorSupport
  defdelegate format_diagnostic_line(diag), to: EditorSupport
  defdelegate assign_tokenization(socket, content, rel_path, opts \\ []), to: EditorSupport
  defdelegate parse_positive_int(value), to: EditorSupport
  defdelegate parse_non_negative_int(value), to: EditorSupport
  defdelegate parse_non_negative_number(value), to: EditorSupport
  defdelegate completion_replace_range(content, cursor), to: EditorSupport
  defdelegate maybe_put_state(state, key, value), to: EditorSupport
  defdelegate sync_active_diagnostic_index_to_tab(socket), to: EditorSupport
  defdelegate restore_editor_state(socket, state), to: EditorSupport
  defdelegate focus_diagnostic(socket, direction), to: EditorSupport
  defdelegate elm_source_file?(rel_path), to: EditorSupport
  defdelegate push_editor_lint_diagnostics(socket, diagnostics), to: EditorSupport

  @spec tab_with_save_content(map(), map()) :: map()
  defp tab_with_save_content(tab, %{"content" => content}) when is_binary(content) do
    %{tab | content: content}
  end

  defp tab_with_save_content(tab, %{"editor" => %{"content" => content}})
       when is_binary(content) do
    %{tab | content: content}
  end

  defp tab_with_save_content(tab, _params), do: tab

  @spec creatable_source_roots(Project.t() | nil) :: [String.t()]
  defp creatable_source_roots(%Project{} = project) do
    workspace_root = Projects.project_workspace_path(project)

    project.source_roots
    |> List.wrap()
    |> Enum.reject(&(&1 == "protocol"))
    |> Enum.filter(fn source_root ->
      File.exists?(Path.join([workspace_root, source_root, "elm.json"]))
    end)
    |> case do
      [] -> ["watch"]
      roots -> roots
    end
  end

  defp creatable_source_roots(_project), do: ["watch"]

  @spec validate_creatable_source_root(Project.t() | nil, term()) ::
          :ok | {:error, :invalid_source_root}
  defp validate_creatable_source_root(project, source_root) do
    if source_root in creatable_source_roots(project),
      do: :ok,
      else: {:error, :invalid_source_root}
  end

  defdelegate format_source(project, tab, formatter_backend, parser_payload, tokens),
    to: EditorSupport

  defdelegate prepare_content_for_save(
                project,
                tab,
                auto_format_enabled,
                formatter_backend,
                parser_payload,
                tokens
              ),
              to: EditorSupport

  @spec debugger_import_error(term()) :: term()
  defp debugger_import_error(:invalid_json), do: "Trace import failed: invalid JSON."

  defp debugger_import_error(:invalid_trace),
    do:
      "Trace import failed: not a valid export (need export_version 1, events, watch, companion, seq)."

  defp debugger_import_error(:slug_mismatch),
    do: "Trace import failed: project_slug in JSON does not match this project."

  @spec package_add_error(term()) :: String.t()
  defp package_add_error({:package_not_supported_for_phone, package}) do
    "Could not add #{package}: this package is not supported for the companion phone elm.json."
  end

  defp package_add_error(reason), do: "Could not add package: #{inspect(reason)}"

  @spec mark_dependency_used(term(), String.t()) :: term()
  defp mark_dependency_used(socket, package) when is_binary(package) do
    socket
    |> assign(
      :project_elm_direct,
      mark_dependency_rows_used(socket.assigns[:project_elm_direct], package)
    )
    |> assign(
      :project_elm_indirect,
      mark_dependency_rows_used(socket.assigns[:project_elm_indirect], package)
    )
  end

  @spec mark_dependency_rows_used(term(), String.t()) :: [map()]
  defp mark_dependency_rows_used(rows, package) when is_list(rows) and is_binary(package) do
    Enum.map(rows, fn
      %{name: ^package} = row -> Map.put(row, :used?, true)
      %{"name" => ^package} = row -> Map.put(row, :used?, true)
      row -> row
    end)
  end

  defp mark_dependency_rows_used(_rows, _package), do: []

  @spec pane_class(term(), term()) :: term()
  defp pane_class(active, pane) when active == pane,
    do: "rounded bg-blue-100 px-3 py-2 text-blue-800"

  defp pane_class(_active, _pane), do: "rounded bg-zinc-100 px-3 py-2"

  @spec load_editor_doc_body(term(), term(), term(), term()) :: term()
  defp load_editor_doc_body(socket, package, version, module) do
    package = to_string(package)

    version =
      case version do
        nil -> "latest"
        "" -> "latest"
        v -> to_string(v)
      end

    module = module |> to_string() |> String.trim()
    opts = []
    ver_display = version

    {markdown, header} =
      cond do
        module != "" ->
          case Packages.module_doc_markdown(package, version, module, opts) do
            {:ok, doc} when is_binary(doc) ->
              if String.trim(doc) != "" do
                ref_url = EditorDocLinks.package_elm_doc_url(package, module, "")
                mod_esc = String.replace(module, "`", "")

                intro =
                  """
                  **Package:** `#{package}` (#{ver_display})

                  **Module:** `#{mod_esc}`

                  **Also on the web:** [package.elm-lang.org](#{ref_url})

                  ---

                  """

                {doc, intro}
              else
                editor_module_doc_readme_fallback(package, version, module, ver_display, opts)
              end

            _ ->
              editor_module_doc_readme_fallback(package, version, module, ver_display, opts)
          end

        true ->
          {editor_package_readme_slice(package, version, opts), ""}
      end

    assign(socket, :editor_doc_html, Markdown.readme_to_html(header <> markdown))
  end

  @spec editor_package_readme_slice(term(), term(), term()) :: term()
  defp editor_package_readme_slice(package, version, opts) do
    case Packages.readme(package, version, opts) do
      {:ok, payload} -> String.slice(payload.readme || "", 0, 12_000)
      _ -> "_Could not load README for `#{package}` at `#{version}`._"
    end
  end

  @spec editor_module_doc_readme_fallback(term(), term(), term(), term(), term()) :: term()
  defp editor_module_doc_readme_fallback(package, version, module, ver_display, opts) do
    readme = editor_package_readme_slice(package, version, opts)
    ref_url = EditorDocLinks.package_elm_doc_url(package, module, "")
    mod_esc = String.replace(module, "`", "")

    intro =
      """
      **Package:** `#{package}` (#{ver_display})

      **Module:** `#{mod_esc}`

      **Also on the web:** [package.elm-lang.org](#{ref_url})

      _Registry module documentation is not available for this package or version (for example unpublished platform sources). Showing the package README instead._

      ---

      """

    {readme, intro}
  end

  @spec apply_doc_catalog_rows(term(), term()) :: term()
  defp apply_doc_catalog_rows(socket, rows) when is_list(rows) do
    socket = assign(socket, :editor_doc_packages, rows)

    cond do
      rows == [] ->
        socket
        |> assign(:editor_doc_package, nil)
        |> assign(:editor_doc_module, "")
        |> assign(:editor_doc_html, "")

      socket.assigns[:editor_doc_package] == nil ->
        init_editor_doc_selection(socket, hd(rows))

      not Enum.any?(rows, &(&1.package == socket.assigns.editor_doc_package)) ->
        init_editor_doc_selection(socket, hd(rows))

      true ->
        row = Enum.find(rows, &(&1.package == socket.assigns.editor_doc_package))
        cur_mod = socket.assigns[:editor_doc_module] || ""

        {mod, socket} =
          cond do
            (cur_mod != "" and row) && cur_mod in row.modules ->
              {cur_mod, assign(socket, :editor_doc_module, cur_mod)}

            row && row.modules != [] ->
              m = hd(row.modules)
              {m, assign(socket, :editor_doc_module, m)}

            true ->
              {"", assign(socket, :editor_doc_module, "")}
          end

        if row do
          load_editor_doc_body(socket, row.package, row.version, mod)
        else
          socket
        end
    end
  end

  @spec init_editor_doc_selection(term(), term()) :: term()
  defp init_editor_doc_selection(socket, row) do
    mod = List.first(row.modules) || ""

    socket
    |> assign(:editor_doc_package, row.package)
    |> assign(:editor_doc_module, mod)
    |> load_editor_doc_body(row.package, row.version, mod)
  end

  @doc false
  @spec editor_doc_modules_for_package(term(), term(), term()) :: term()
  def editor_doc_modules_for_package(rows, pkg, query \\ "")

  def editor_doc_modules_for_package(rows, pkg, query) when is_list(rows) and is_binary(pkg) do
    modules =
      case Enum.find(rows, &(&1.package == pkg)) do
        %{modules: mods} when is_list(mods) -> mods
        _ -> []
      end

    filter_editor_doc_modules(modules, query)
  end

  def editor_doc_modules_for_package(_, _, _), do: []

  @spec filter_editor_doc_modules([String.t()], term()) :: [String.t()]
  defp filter_editor_doc_modules(modules, query) when is_list(modules) do
    needle = query |> to_string() |> String.trim() |> String.downcase()

    if needle == "" do
      modules
    else
      Enum.filter(modules, fn mod ->
        mod
        |> to_string()
        |> String.downcase()
        |> String.contains?(needle)
      end)
    end
  end

  defdelegate schedule_compiler_check(socket), to: BuildFlow
  defdelegate warm_debugger_compile_context(socket, project), to: BuildFlow

  @spec maybe_refresh_debugger(term()) :: term()
  defp maybe_refresh_debugger(socket) do
    if socket.assigns[:pane] == :debugger do
      DebuggerSupport.refresh(socket)
    else
      socket
    end
  end

  @spec schedule_editor_check(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  defp schedule_editor_check(socket, %{source_root: source_root, rel_path: rel_path}) do
    case socket.assigns[:project] do
      nil ->
        socket

      project ->
        token = System.unique_integer([:positive])
        workspace_root = Projects.project_workspace_path(project)

        socket
        |> assign(:editor_check_status, :running)
        |> assign(:editor_check_token, token)
        |> assign(:editor_check_source_root, source_root)
        |> assign(:editor_check_rel_path, rel_path)
        |> assign(:editor_check_diagnostics, [])
        |> assign(:editor_check_output, nil)
        |> start_async(:editor_check, fn ->
          result =
            Compiler.check_source_root("#{project.slug}:editor:#{source_root}",
              workspace_root: workspace_root,
              source_root: source_root
            )

          {result, token, source_root, rel_path}
        end)
    end
  end

  @spec clear_editor_check(Phoenix.LiveView.Socket.t(), map() | nil) ::
          Phoenix.LiveView.Socket.t()
  defp clear_editor_check(socket, %{source_root: source_root, rel_path: rel_path}) do
    if socket.assigns[:editor_check_source_root] == source_root and
         socket.assigns[:editor_check_rel_path] == rel_path do
      socket
      |> assign(:editor_check_status, :idle)
      |> assign(:editor_check_token, nil)
      |> assign(:editor_check_diagnostics, [])
      |> assign(:editor_check_output, nil)
    else
      socket
    end
  end

  defp clear_editor_check(socket, _tab), do: socket

  @spec push_editor_check_lint_diagnostics(
          Phoenix.LiveView.Socket.t(),
          String.t(),
          String.t(),
          [map()]
        ) :: Phoenix.LiveView.Socket.t()
  defp push_editor_check_lint_diagnostics(socket, source_root, rel_path, diagnostics) do
    case active_tab(socket) do
      %{source_root: ^source_root, rel_path: ^rel_path} ->
        diagnostics
        |> Enum.filter(&editor_check_diagnostic_matches_rel_path?(&1, rel_path))
        |> then(&push_editor_lint_diagnostics(socket, &1))

      _ ->
        socket
    end
  end

  @spec editor_check_diagnostic_matches_rel_path?(map(), String.t()) :: boolean()
  defp editor_check_diagnostic_matches_rel_path?(diag, rel_path)
       when is_map(diag) and is_binary(rel_path) do
    case Map.get(diag, :file) || Map.get(diag, "file") do
      nil -> true
      ^rel_path -> true
      _other -> false
    end
  end

  defdelegate run_emulator_install_flow(project, workspace_root, emulator_target, package_path),
    to: BuildFlow

  @spec maybe_check_emulator_installation(Phoenix.LiveView.Socket.t()) ::
          Phoenix.LiveView.Socket.t()
  defp maybe_check_emulator_installation(socket) do
    if socket.assigns[:live_action] == :emulator do
      check_emulator_installation(socket)
    else
      socket
    end
  end

  @spec check_emulator_installation(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp check_emulator_installation(socket) do
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

  @spec debugger_session_active?(term()) :: term()
  defp debugger_session_active?(socket) do
    debugger_state_running?(socket.assigns[:debugger_state])
  end

  @spec debugger_state_running?(term()) :: boolean()
  defp debugger_state_running?(%{running: true}), do: true
  defp debugger_state_running?(_), do: false

  @spec bootstrap_debugger_preview(Phoenix.LiveView.Socket.t(), Projects.Project.t()) ::
          {Phoenix.LiveView.Socket.t(), String.t()}
  defp bootstrap_debugger_preview(socket, project) do
    case debugger_bootstrap_elm_source(project, socket) do
      {:ok, rel_path, content, source_root} ->
        maybe_bootstrap_companion_debugger(project)

        case Ide.Debugger.reload(project.slug, %{
               rel_path: rel_path,
               source: content,
               reason: "debugger_bootstrap",
               source_root: source_root
             }) do
          {:ok, _} ->
            {DebuggerSupport.refresh(socket),
             "Debugger started. Loaded #{editor_source_display_path(rel_path)}; watch preview uses parser snapshots when the view outline parses."}
        end

      :error ->
        {socket,
         "Debugger started. Open an Elm tab or add Main.elm under the watch source tree, then save a file to load the sample preview."}
    end
  end

  @spec maybe_bootstrap_companion_debugger(Projects.Project.t()) :: :ok
  defp maybe_bootstrap_companion_debugger(project) do
    case Projects.read_source_file(project, "phone", "src/CompanionApp.elm") do
      {:ok, content} ->
        _ =
          Ide.Debugger.reload(project.slug, %{
            rel_path: "src/CompanionApp.elm",
            source: content,
            reason: "debugger_companion_bootstrap",
            source_root: "protocol"
          })

        :ok

      {:error, _} ->
        :ok
    end
  end

  @spec debugger_bootstrap_elm_source(term(), term()) :: term()
  defp debugger_bootstrap_elm_source(project, socket) do
    case active_tab(socket) do
      %{rel_path: rel_path, content: content, source_root: "watch"} = tab ->
        if elm_bootstrap_tab?(tab) do
          {:ok, rel_path, content, "watch"}
        else
          try_read_watch_main_elm(project)
        end

      _ ->
        try_read_watch_main_elm(project)
    end
  end

  @spec elm_bootstrap_tab?(term()) :: term()
  defp elm_bootstrap_tab?(%{rel_path: p, content: c})
       when is_binary(p) and is_binary(c) do
    String.ends_with?(p, ".elm")
  end

  defp elm_bootstrap_tab?(_), do: false

  @spec try_read_watch_main_elm(term()) :: term()
  defp try_read_watch_main_elm(project) do
    candidates = [{"watch", "src/Main.elm"}, {"watch", "Main.elm"}]

    Enum.reduce_while(candidates, :error, fn {root, path}, _ ->
      case Projects.read_source_file(project, root, path) do
        {:ok, content} -> {:halt, {:ok, path, content, root}}
        {:error, _} -> {:cont, :error}
      end
    end)
  end

  @spec merge_publish_submit_options(term(), term()) :: term()
  defp merge_publish_submit_options(existing, updates)
       when is_map(existing) and is_map(updates) do
    existing
    |> Map.merge(%{
      "is_published" => to_bool(Map.get(updates, "is_published")),
      "all_platforms" => to_bool(Map.get(updates, "all_platforms"))
    })
  end

  @spec to_bool(term()) :: term()
  defp to_bool(value) when value in [true, "true", "on", "1", 1], do: true
  defp to_bool(_), do: false

  @spec atomize_screenshot(map()) :: map()
  defp atomize_screenshot(screenshot) when is_map(screenshot) do
    %{
      filename: Map.get(screenshot, "filename") || Map.get(screenshot, :filename),
      emulator_target:
        Map.get(screenshot, "emulator_target") || Map.get(screenshot, :emulator_target),
      url: Map.get(screenshot, "url") || Map.get(screenshot, :url),
      absolute_path: Map.get(screenshot, "absolute_path") || Map.get(screenshot, :absolute_path),
      captured_at: Map.get(screenshot, "captured_at") || Map.get(screenshot, :captured_at)
    }
  end

  defdelegate render_capture_all_progress(msg), to: EmulatorFlow
  defdelegate update_capture_target_statuses(statuses, msg), to: EmulatorFlow
  defdelegate maybe_merge_capture_progress_screenshot(socket, msg), to: EmulatorFlow
  defdelegate merge_capture_all_result_statuses(statuses, result), to: EmulatorFlow
  defdelegate emulator_install_error_message(reason), to: EmulatorFlow

  defdelegate bitmap_upload_output(results), to: ResourcesFlow
  defdelegate font_upload_output(results), to: ResourcesFlow
  defdelegate load_bitmap_resources(project), to: ResourcesFlow
  defdelegate load_font_sources(project), to: ResourcesFlow
  defdelegate load_font_resources(project), to: ResourcesFlow
  defdelegate load_screenshots(project), to: ResourcesFlow
  defdelegate group_screenshots(shots), to: ResourcesFlow

  @spec persist_project_publish_metadata(term(), term(), term()) :: term()
  defp persist_project_publish_metadata(
         %Project{} = project,
         submitted_release_summary,
         next_release_summary
       ) do
    attrs =
      project
      |> PublishFlow.publish_project_attrs_from_submit(submitted_release_summary)
      |> Map.update!("release_defaults", fn defaults ->
        defaults
        |> Map.put("version_label", next_release_summary["version_label"] || "")
        |> Map.put("tags", next_release_summary["tags"] || "")
      end)

    case Projects.update_project(project, attrs) do
      {:ok, updated} -> updated
      {:error, _} -> project
    end
  end

  @spec persist_project_debugger_timeline_mode(Project.t(), String.t()) :: Project.t()
  defp persist_project_debugger_timeline_mode(%Project{} = project, mode)
       when mode in ["watch", "companion", "mixed", "separate"] do
    settings = project.debugger_settings || %{}
    updated_settings = Map.put(settings, "timeline_mode", mode)

    case Projects.update_project(project, %{"debugger_settings" => updated_settings}) do
      {:ok, updated} -> updated
      {:error, _} -> project
    end
  end

  defp persist_project_debugger_timeline_mode(project, _mode), do: project

  @spec persist_project_emulator_target(Project.t() | term(), term()) :: term()
  defp persist_project_emulator_target(%Project{} = project, target) do
    selected = normalize_emulator_target(target)
    settings = project.debugger_settings || %{}
    updated_settings = Map.put(settings, "emulator_target", selected)

    case Projects.update_project(project, %{"debugger_settings" => updated_settings}) do
      {:ok, updated} -> updated
      {:error, _} -> project
    end
  end

  defp persist_project_emulator_target(project, _target), do: project

  @spec persist_project_emulator_mode(Project.t() | term(), term()) :: term()
  defp persist_project_emulator_mode(%Project{} = project, mode) do
    selected = normalize_emulator_mode(mode)
    settings = project.debugger_settings || %{}
    updated_settings = Map.put(settings, "emulator_mode", selected)

    case Projects.update_project(project, %{"debugger_settings" => updated_settings}) do
      {:ok, updated} -> updated
      {:error, _} -> project
    end
  end

  defp persist_project_emulator_mode(project, _mode), do: project

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
  defp project_debugger_timeline_mode(%Project{} = project) do
    settings = project.debugger_settings || %{}

    case Map.get(settings, "timeline_mode") do
      mode when mode in ["watch", "companion", "mixed", "separate"] -> mode
      _ -> "mixed"
    end
  end

  @spec project_emulator_target(term()) :: String.t()
  defp project_emulator_target(%Project{} = project) do
    settings = project.debugger_settings || %{}
    normalize_emulator_target(Map.get(settings, "emulator_target"))
  end

  defp project_emulator_target(_), do: default_emulator_target()

  @spec project_emulator_mode(term()) :: String.t()
  defp project_emulator_mode(%Project{} = project) do
    settings = project.debugger_settings || %{}
    normalize_emulator_mode(Map.get(settings, "emulator_mode"))
  end

  defp project_emulator_mode(_), do: "embedded"

  @spec project_debugger_watch_profile_id(Project.t()) :: String.t()
  defp project_debugger_watch_profile_id(%Project{} = project) do
    settings = project.debugger_settings || %{}
    normalize_debugger_watch_profile_id(Map.get(settings, "watch_profile_id"))
  end

  @spec normalize_debugger_watch_profile_id(term()) :: String.t()
  defp normalize_debugger_watch_profile_id(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()

    if normalized in debugger_watch_profile_ids(),
      do: normalized,
      else: default_debugger_watch_profile_id()
  end

  defp normalize_debugger_watch_profile_id(_), do: default_debugger_watch_profile_id()

  @spec debugger_watch_profile_ids() :: [String.t()]
  defp debugger_watch_profile_ids do
    Ide.Debugger.watch_profiles()
    |> Enum.map(&Map.get(&1, "id"))
    |> Enum.filter(&is_binary/1)
  end

  @spec open_debugger_trigger_modal(term(), map()) :: term()
  defp open_debugger_trigger_modal(socket, params) when is_map(params) do
    trigger = Map.get(params, "trigger") || ""
    target = Map.get(params, "target") || "watch"
    message = Map.get(params, "message") || ""
    form_data = default_debugger_trigger_form(trigger, target, message)

    assign(socket,
      debugger_trigger_modal_open: true,
      debugger_trigger_form: to_form(form_data, as: :debugger_trigger)
    )
  end

  @spec debugger_trigger_modal_supported?(term(), map()) :: boolean()
  defp debugger_trigger_modal_supported?(socket, params) when is_map(params) do
    state = socket.assigns[:debugger_state]

    row = %{
      trigger: Map.get(params, "trigger") || Map.get(params, :trigger),
      target: Map.get(params, "target") || Map.get(params, :target),
      message: Map.get(params, "message") || Map.get(params, :message)
    }

    Ide.Debugger.subscription_trigger_injection_modal_supported?(state, row)
  end

  defp debugger_trigger_modal_supported?(_socket, _params), do: false

  @spec close_debugger_trigger_modal(term()) :: term()
  defp close_debugger_trigger_modal(socket) do
    assign(socket,
      debugger_trigger_modal_open: false,
      debugger_trigger_form: to_form(%{}, as: :debugger_trigger)
    )
  end

  @spec default_debugger_trigger_form(term(), term(), term()) :: map()
  defp default_debugger_trigger_form(trigger, target, message) do
    constructor =
      case message do
        value when is_binary(value) and value != "" -> value
        _ -> default_debugger_message_for_trigger(trigger)
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

        contains_any?(normalized_trigger, ["on_tick", "ontick", "tick"]) ->
          {"integer", Integer.to_string(now.second),
           append_single_payload(constructor, now.second)}

        true ->
          {"message", "", constructor}
      end

    %{
      "target" => target,
      "trigger" => trigger,
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
        auto_fire_trigger_available?(project.slug, target, trigger) do
      {:ok, _state} =
        Ide.Debugger.set_subscription_enabled(project.slug, %{
          target: target,
          trigger: trigger,
          enabled: false
        })
    end

    for %{"target" => target, "trigger" => trigger} <-
          Map.get(settings, "auto_fire_subscriptions", []),
        auto_fire_trigger_available?(project.slug, target, trigger) do
      {:ok, _state} =
        Ide.Debugger.set_auto_fire(project.slug, %{
          target: target,
          trigger: trigger,
          enabled: true
        })
    end

    if Map.get(settings, "auto_fire_subscriptions", []) == [] do
      for target <- ["watch", "protocol"],
          debugger_auto_fire_enabled?(project, target),
          auto_fire_available?(project.slug, target) do
        {:ok, _state} =
          Ide.Debugger.set_auto_fire(project.slug, %{
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

  @spec maybe_schedule_debugger_auto_fire_refresh(term()) :: term()
  defp maybe_schedule_debugger_auto_fire_refresh(socket) do
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

  @spec debugger_auto_fire_refresh_active?(term()) :: boolean()
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

  @spec debugger_auto_fire_refresh_interval_ms(term()) :: pos_integer()
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

  @spec debugger_auto_fire_enabled?(Project.t(), term()) :: boolean()
  defp debugger_auto_fire_enabled?(%Project{} = project, target) do
    settings = project.debugger_settings || %{}
    auto_fire = Map.get(settings, "auto_fire", %{})
    Map.get(auto_fire, debugger_auto_fire_target(target)) == true
  end

  @spec debugger_auto_fire_target(term()) :: String.t()
  defp debugger_auto_fire_target("protocol"), do: "protocol"
  defp debugger_auto_fire_target("companion"), do: "phone"
  defp debugger_auto_fire_target(:protocol), do: "protocol"
  defp debugger_auto_fire_target(:companion), do: "phone"
  defp debugger_auto_fire_target(_target), do: "watch"

  @spec debugger_checkbox_enabled?(term()) :: boolean()
  defp debugger_checkbox_enabled?(value) when value in [true, "true", "on", "1", 1], do: true
  defp debugger_checkbox_enabled?(_value), do: false

  @spec maybe_warn_uncommitted_prepare_release(term(), term()) :: term()
  defp maybe_warn_uncommitted_prepare_release(socket, workspace_root) do
    case workspace_uncommitted_changes(workspace_root) do
      {:ok, 0} ->
        socket

      {:ok, count} ->
        put_flash(
          socket,
          :error,
          "Prepare Release warning: #{count} uncommitted change(s) detected in project workspace."
        )

      _ ->
        socket
    end
  end

  @spec workspace_uncommitted_changes(term()) :: {:ok, non_neg_integer()} | {:error, term()}
  defp workspace_uncommitted_changes(workspace_root) when is_binary(workspace_root) do
    case System.cmd("git", ["status", "--porcelain"], cd: workspace_root, stderr_to_stdout: true) do
      {output, 0} ->
        count =
          output
          |> String.split("\n", trim: true)
          |> length()

        {:ok, count}

      {_output, _status} ->
        {:error, :git_unavailable_or_not_repo}
    end
  end

  @spec format_github_push_error(term()) :: String.t()
  defp format_github_push_error({:missing_repo_field, field}),
    do: "Missing repository field: #{field}"

  defp format_github_push_error(:github_not_connected),
    do: "GitHub is not connected. Connect from IDE Settings first."

  defp format_github_push_error({:git_failed, _command, output}), do: output
  defp format_github_push_error(reason), do: inspect(reason)

  @spec default_emulator_target() :: term()
  defp default_emulator_target do
    Application.get_env(:ide, Ide.PebbleToolchain, [])
    |> Keyword.get(:emulator_target, "basalt")
  end

  @spec normalize_emulator_target(term()) :: String.t()
  defp normalize_emulator_target(target) when is_binary(target) do
    target = String.trim(target)
    targets = ToolchainPresenter.emulator_targets()

    cond do
      target in targets -> target
      default_emulator_target() in targets -> default_emulator_target()
      targets != [] -> hd(targets)
      true -> default_emulator_target()
    end
  end

  defp normalize_emulator_target(_), do: normalize_emulator_target(default_emulator_target())

  @spec normalize_emulator_mode(term()) :: String.t()
  defp normalize_emulator_mode(mode) when is_binary(mode) do
    case String.trim(mode) do
      "external" -> "external"
      "wasm" -> "wasm"
      _ -> "embedded"
    end
  end

  defp normalize_emulator_mode(_), do: "embedded"
end
