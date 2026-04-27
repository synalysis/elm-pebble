defmodule IdeWeb.WorkspaceLive do
  use IdeWeb, :live_view

  alias Ide.Compiler
  alias Ide.ElmFormat
  alias Ide.Formatter
  alias Ide.Formatter.EditPatch
  alias Ide.GitHub.Push, as: GitHubPush
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
  alias Ide.Tokenizer
  alias Ide.EditorDocLinks
  alias Ide.Markdown
  alias IdeWeb.WorkspaceLive.EditorDependencies
  alias IdeWeb.WorkspaceLive.EditorPage
  alias IdeWeb.WorkspaceLive.EmulatorPage
  alias IdeWeb.WorkspaceLive.BuildPage
  alias IdeWeb.WorkspaceLive.PublishFlow
  alias IdeWeb.WorkspaceLive.PublishPage
  alias IdeWeb.WorkspaceLive.ProjectSettingsPage
  alias IdeWeb.WorkspaceLive.PackagesPage
  alias IdeWeb.WorkspaceLive.ResourcesPage
  alias IdeWeb.WorkspaceLive.PackagesFlow
  alias IdeWeb.WorkspaceLive.DebuggerSupport
  alias IdeWeb.WorkspaceLive.DebuggerPreview
  alias IdeWeb.WorkspaceLive.DebuggerBridge
  alias IdeWeb.WorkspaceLive.ToolchainPresenter

  @max_editor_highlight_tokens 25_000
  @max_editor_fold_ranges 2_000
  @max_editor_lint_diagnostics 1_000
  @debugger_auto_fire_refresh_interval_ms 1_000
  @min_bracket_fold_span_lines 10
  @protected_editor_rel_paths [
    "src/Main.elm",
    "src/CompanionApp.elm",
    "src/Companion/Types.elm",
    "src/Pebble/Ui/Resources.elm"
  ]
  @debugger_model_metadata_keys ~w(
    last_message
    last_operation
    step_counter
    last_runtime_step_message
    last_runtime_step_op
    runtime_last_message
    runtime_message_source
    runtime_model_source
    protocol_last_inbound_message
    protocol_last_inbound_from
    protocol_inbound_count
    protocol_last_trigger
  )

  @impl true
  @spec mount(term(), term(), term()) :: term()
  def mount(_params, _session, socket) do
    settings = Settings.current()

    {:ok,
     socket
     |> assign(:project, nil)
     |> assign(:pane, :editor)
     |> assign(:tree, [])
     |> assign(:tabs, [])
     |> assign(:active_tab_id, nil)
     |> assign(:opening_file_id, nil)
     |> assign(:opening_file_label, nil)
     |> assign(:file_open_token, nil)
     |> assign(:editor_deps_refresh_token, nil)
     |> assign(:check_status, :idle)
     |> assign(:check_output, nil)
     |> assign(:compile_status, :idle)
     |> assign(:compile_output, nil)
     |> assign(:manifest_status, :idle)
     |> assign(:manifest_output, nil)
     |> assign(:build_status, :idle)
     |> assign(:build_output, nil)
     |> assign(:manifest_strict_mode, false)
     |> assign(:format_status, :idle)
     |> assign(:format_output, nil)
     |> assign(:pebble_build_status, :idle)
     |> assign(:pebble_build_output, nil)
     |> assign(:pebble_install_status, :idle)
     |> assign(:pebble_install_output, nil)
     |> assign(:screenshot_status, :idle)
     |> assign(:screenshot_output, nil)
     |> assign(:capture_all_status, :idle)
     |> assign(:capture_all_output, nil)
     |> assign(:capture_all_progress, nil)
     |> assign(:capture_all_progress_lines, [])
     |> assign(:capture_all_target_statuses, %{})
     |> assign(:capture_all_token, nil)
     |> assign(:screenshots, [])
     |> assign(:screenshot_groups, [])
     |> assign(:emulator_targets, ToolchainPresenter.emulator_targets())
     |> assign(:selected_emulator_target, default_emulator_target())
     |> assign(:emulator_form, to_form(%{"target" => default_emulator_target()}, as: :emulator))
     |> assign(:publish_status, :idle)
     |> assign(:publish_output, nil)
     |> assign(:publish_artifact_path, nil)
     |> assign(:publish_app_root, nil)
     |> assign(:publish_readiness, [])
     |> assign(:publish_checks, [])
     |> assign(:publish_summary, %{status: :idle, blockers: 0, warnings: 0, passed: 0})
     |> assign(:publish_warnings, [])
     |> assign(:publish_type_guidance, PublishFlow.publish_type_guidance(nil, nil))
     |> assign(:manifest_export_status, :idle)
     |> assign(:manifest_export_output, nil)
     |> assign(:manifest_export_path, nil)
     |> assign(:prepare_release_status, :idle)
     |> assign(:prepare_release_output, nil)
     |> assign(:publish_submit_status, :idle)
     |> assign(:publish_submit_output, nil)
     |> assign(:publish_submit_options, %{
       "is_published" => false,
       "all_platforms" => false
     })
     |> assign(:release_summary, PublishFlow.default_release_summary(nil))
     |> assign(
       :release_summary_form,
       to_form(PublishFlow.default_release_summary(nil), as: :release_summary)
     )
     |> assign(:publish_metrics, %{
       total_runs: 0,
       successful_runs: 0,
       last_duration_ms: nil,
       last_finished_at: nil,
       in_ide_completion_rate: "0.00"
     })
     |> assign(:packages_query, "")
     |> assign(:packages_search_results, [])
     |> assign(:packages_search_total, 0)
     |> assign(:packages_search_busy, false)
     |> assign(:packages_search_progress, nil)
     |> assign(:packages_search_token, nil)
     |> assign(:packages_inspect_loading, nil)
     |> assign(:packages_selected, nil)
     |> assign(:packages_details, nil)
     |> assign(:packages_versions, [])
     |> assign(:packages_readme, nil)
     |> assign(:packages_preview, nil)
     |> assign(:packages_target_root, "watch")
     |> assign(:packages_last_add_result, nil)
     |> assign(:create_file_modal_open, false)
     |> assign(:rename_file_modal_open, false)
     |> assign(:project_elm_direct, [])
     |> assign(:project_elm_indirect, [])
     |> assign(:package_doc_index, %{})
     |> assign(:editor_context_menu, nil)
     |> assign(:packages_dep_readme, nil)
     |> assign(:packages_dep_docs_package, nil)
     |> assign(:packages_dep_docs_version, nil)
     |> assign(:editor_docs_panel_open, false)
     |> assign(:editor_docs_col_px, 352)
     |> assign(:editor_doc_package, nil)
     |> assign(:editor_doc_module, "")
     |> assign(:editor_doc_query, "")
     |> assign(:editor_doc_packages, [])
     |> assign(:editor_doc_html, "")
     |> assign(:release_notes_status, :idle)
     |> assign(:release_notes_output, nil)
     |> assign(:release_notes_path, nil)
     |> assign(:token_summary, nil)
     |> assign(:token_tokens, [])
     |> assign(:token_diagnostics, [])
     |> assign(:formatter_parser_payload, nil)
     |> assign(:tokenizer_mode, :fast)
     |> assign(:editor_line_count, 1)
     |> assign(:token_diag_by_line, %{})
     |> assign(:editor_inline_diagnostics, [])
     |> assign(:active_diagnostic_index, nil)
     |> assign(:auto_format_on_save, settings.auto_format_on_save)
     |> assign(:formatter_backend, settings.formatter_backend)
     |> assign(:debug_mode, settings.debug_mode)
     |> assign(:editor_mode, settings.editor_mode)
     |> assign(:editor_theme, settings.editor_theme)
     |> assign(:editor_line_numbers, settings.editor_line_numbers)
     |> assign(:editor_active_line_highlight, settings.editor_active_line_highlight)
     |> assign(:debugger_auto_fire_refresh_scheduled, false)
     |> assign(:expanded_tree_dirs, MapSet.new())
     |> assign(
       :project_settings_form,
       to_form(project_settings_form_data(nil), as: :project_settings)
     )
     |> assign(:github_push_status, :idle)
     |> assign(:github_push_output, nil)
     |> assign(:auto_format_last_result, nil)
     |> assign(:bitmap_resources, [])
     |> assign(:bitmap_upload_output, nil)
     |> assign(:font_resources, [])
     |> assign(:font_upload_output, nil)
     |> assign(
       :new_file_form,
       to_form(%{"source_root" => "watch", "rel_path" => ""}, as: :new_file)
     )
     |> assign(:rename_form, to_form(%{"new_rel_path" => ""}, as: :rename))
     |> assign(:diagnostics, [])
     |> allow_upload(:bitmap,
       accept: ~w(.png .bmp .jpg .jpeg .gif .webp),
       max_entries: 1,
       max_file_size: 2_500_000
     )
     |> allow_upload(:font,
       accept: ~w(.ttf .otf),
       max_entries: 1,
       max_file_size: 2_500_000
     )
     |> DebuggerSupport.assign_defaults()}
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
        font_resources = load_font_resources(project)
        screenshots = load_screenshots(project)
        screenshot_groups = group_screenshots(screenshots)

        publish_readiness = PublishFlow.publish_readiness(screenshots)

        {:noreply,
         socket
         |> assign(:project, project)
         |> DebuggerSupport.set_debugger_timeline_mode(project_debugger_timeline_mode(project))
         |> assign(:debugger_trace_export, nil)
         |> assign(:debugger_trace_export_context, nil)
         |> assign(:debugger_export_form, DebuggerSupport.export_trace_form())
         |> assign(:debugger_import_form, DebuggerSupport.import_trace_form())
         |> assign(:pane, socket.assigns.live_action)
         |> assign(:tree, tree)
         |> assign(:bitmap_resources, bitmap_resources)
         |> assign(:font_resources, font_resources)
         |> assign(:screenshots, screenshots)
         |> assign(:screenshot_groups, screenshot_groups)
         |> assign(:publish_readiness, publish_readiness)
         |> assign(
           :capture_all_target_statuses,
           socket.assigns.capture_all_target_statuses || %{}
         )
         |> assign(:publish_summary, PublishFlow.publish_summary([], [], publish_readiness))
         |> assign(:publish_warnings, [])
         |> assign(
           :publish_type_guidance,
           PublishFlow.publish_type_guidance(project, publish_readiness)
         )
         |> assign(:release_summary, PublishFlow.default_release_summary(project))
         |> assign(
           :release_summary_form,
           to_form(PublishFlow.default_release_summary(project), as: :release_summary)
         )
         |> assign(:auto_format_on_save, settings.auto_format_on_save)
         |> assign(:formatter_backend, settings.formatter_backend)
         |> assign(:debug_mode, settings.debug_mode)
         |> assign(:editor_mode, settings.editor_mode)
         |> assign(:editor_theme, settings.editor_theme)
         |> assign(:editor_line_numbers, settings.editor_line_numbers)
         |> assign(:editor_active_line_highlight, settings.editor_active_line_highlight)
         |> assign(:expanded_tree_dirs, MapSet.new())
         |> assign(
           :project_settings_form,
           to_form(project_settings_form_data(project), as: :project_settings)
         )
         |> assign(:github_push_status, :idle)
         |> assign(:github_push_output, nil)
         |> assign(:packages_target_root, preferred_packages_target_root(socket, project))
         |> assign(
           :emulator_form,
           to_form(%{"target" => socket.assigns.selected_emulator_target}, as: :emulator)
         )
         |> assign(:page_title, "#{project.name} · #{Atom.to_string(socket.assigns.live_action)}")
         |> maybe_initialize_forms(project)
         |> maybe_open_editor_default_file(project, previous_pane)
         |> refresh_editor_dependencies()
         |> DebuggerSupport.refresh()
         |> maybe_schedule_debugger_auto_fire_refresh()}
    end
  end

  @impl true
  @spec handle_event(term(), term(), term()) :: term()
  def handle_event("open-file", %{"source-root" => source_root, "rel-path" => rel_path}, socket) do
    tab_id = tab_id(source_root, rel_path)
    existing_tab = Enum.find(socket.assigns.tabs, &(&1.id == tab_id))

    if existing_tab do
      selected_state = existing_tab.editor_state || %{}

      {:noreply,
       socket
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

    with {:ok, module_name} <- module_name_from_rel_path(rel_path),
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
        {:noreply, put_flash(socket, :error, "Generated resources module is read-only.")}

      {:error, :protected_file} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Main.elm, CompanionApp.elm, Companion/Types.elm, and Pebble/Ui/Resources.elm cannot be renamed."
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
            {:noreply, put_flash(socket, :error, "Generated resources module is read-only.")}

          {:error, :protected_file} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "Main.elm, CompanionApp.elm, Companion/Types.elm, and Pebble/Ui/Resources.elm cannot be deleted."
             )}
        end
    end
  end

  def handle_event("select-tab", %{"id" => id}, socket) do
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

    if read_only_tab?(active) do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> update_tab(fn tab -> %{tab | content: content, dirty: true} end)
       |> assign_tokenization(content, active_rel_path)}
    end
  end

  def handle_event("editor-change", %{"content" => content}, socket) do
    active = active_tab(socket)
    active_rel_path = active && active.rel_path

    if read_only_tab?(active) do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> update_tab(fn tab -> %{tab | content: content, dirty: true} end)
       |> assign_tokenization(content, active_rel_path)}
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

  def handle_event("format-file", params, socket) do
    case active_tab(socket) do
      nil ->
        {:noreply, put_flash(socket, :error, "No active file to format.")}

      tab ->
        tab =
          case params do
            %{"content" => content} when is_binary(content) -> %{tab | content: content}
            _ -> tab
          end

        if read_only_tab?(tab) do
          {:noreply, put_flash(socket, :error, "Generated resources module is read-only.")}
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

  def handle_event("save-file", _params, socket) do
    case active_tab(socket) do
      nil ->
        {:noreply, put_flash(socket, :error, "No active file to save.")}

      tab ->
        if read_only_tab?(tab) do
          {:noreply, put_flash(socket, :error, "Generated resources module is read-only.")}
        else
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
      consume_uploaded_entries(socket, :bitmap, fn %{path: path, client_name: client_name},
                                                   _entry ->
        case Projects.import_bitmap_resource(project, path, client_name) do
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
      consume_uploaded_entries(socket, :font, fn %{path: path, client_name: client_name},
                                                 _entry ->
        case Projects.import_font_resource(project, path, client_name) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:ok, %{error: inspect(reason)}}
        end
      end)

    socket =
      socket
      |> assign(:font_resources, load_font_resources(project))
      |> assign(:font_upload_output, font_upload_output(results))
      |> refresh_tree()

    {:noreply, socket}
  end

  def handle_event("delete-font-resource", %{"ctor" => ctor}, socket) do
    case Projects.delete_font_resource(socket.assigns.project, ctor) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:font_resources, load_font_resources(socket.assigns.project))
         |> refresh_tree()
         |> put_flash(:info, "Deleted font #{ctor}.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not delete font: #{inspect(reason)}")}
    end
  end

  def handle_event("run-check", _params, socket) do
    {:noreply, schedule_compiler_check(socket)}
  end

  def handle_event("run-build", _params, socket) do
    project = socket.assigns.project
    workspace_root = Projects.project_workspace_path(project)
    strict? = socket.assigns.manifest_strict_mode

    {:noreply,
     socket
     |> assign(:build_status, :running)
     |> assign(:check_status, :running)
     |> assign(:compile_status, :running)
     |> assign(:manifest_status, :running)
     |> start_async(:run_build, fn ->
       run_build_pipeline(project, workspace_root, strict?)
     end)}
  end

  def handle_event("run-compile", _params, socket) do
    project = socket.assigns.project
    workspace_root = Projects.project_workspace_path(project)

    {:noreply,
     socket
     |> assign(:compile_status, :running)
     |> start_async(:run_compile, fn ->
       Compiler.compile(project.slug, workspace_root: workspace_root)
     end)}
  end

  def handle_event("run-manifest", _params, socket) do
    project = socket.assigns.project
    workspace_root = Projects.project_workspace_path(project)
    strict? = socket.assigns.manifest_strict_mode

    {:noreply,
     socket
     |> assign(:manifest_status, :running)
     |> start_async(:run_manifest, fn ->
       Compiler.manifest(project.slug, workspace_root: workspace_root, strict: strict?)
     end)}
  end

  def handle_event("set-manifest-strict", %{"value" => value}, socket) do
    strict? = value in ["true", true]
    {:noreply, assign(socket, :manifest_strict_mode, strict?)}
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
         |> assign(:packages_last_add_result, result)
         |> refresh_tree()
         |> PackagesFlow.refresh_preview()
         |> put_flash(:info, message)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not add package: #{inspect(reason)}")}
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

    {:noreply,
     socket
     |> assign(:create_file_modal_open, true)
     |> assign(
       :new_file_form,
       to_form(
         %{"source_root" => List.first(project.source_roots) || "watch", "rel_path" => ""},
         as: :new_file
       )
     )}
  end

  def handle_event("close-create-file-modal", _params, socket) do
    {:noreply, assign(socket, :create_file_modal_open, false)}
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
            {:noreply, put_flash(socket, :error, "Generated resources module is read-only.")}

          {:error, :protected_file} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "Main.elm, CompanionApp.elm, Companion/Types.elm, and Pebble/Ui/Resources.elm cannot be renamed."
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
     |> start_async(:run_emulator_install, fn ->
       run_emulator_install_flow(
         project,
         workspace_root,
         emulator_target,
         package_path
       )
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
    github_owner = String.trim(params["github_owner"] || "")
    github_repo = String.trim(params["github_repo"] || "")
    github_branch = String.trim(params["github_branch"] || "")

    attrs = %{
      "release_defaults" =>
        defaults
        |> Map.put("version_label", version_label)
        |> Map.put("tags", tags),
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
           to_form(project_settings_form_data(updated), as: :project_settings)
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

  def handle_event("set-emulator-target", %{"emulator" => %{"target" => target}}, socket) do
    {:noreply,
     socket
     |> assign(:selected_emulator_target, target)
     |> assign(:emulator_form, to_form(%{"target" => target}, as: :emulator))}
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

        socket = socket |> DebuggerSupport.refresh()
        socket = warm_debugger_compile_context(socket, project)

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
    {:noreply, open_debugger_trigger_modal(socket, params)}
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
          message: Map.get(params, "message")
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

  @impl true
  @spec handle_async(term(), term(), term()) :: term()
  def handle_async(:run_check, {:ok, {:ok, result}}, socket) do
    socket =
      socket
      |> assign(:check_status, result.status)
      |> assign(:check_output, result.output)
      |> assign(:diagnostics, result.diagnostics)

    socket = DebuggerBridge.sync_check(socket, result)
    {:noreply, socket}
  end

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

  def handle_async(:refresh_editor_dependencies, {:ok, {payload, token}}, socket) do
    if socket.assigns.editor_deps_refresh_token == token do
      socket =
        socket
        |> assign(:editor_deps_refresh_token, nil)
        |> assign(:package_doc_index, payload.package_doc_index)
        |> apply_doc_catalog_rows(payload.editor_doc_packages)

      socket =
        if Map.get(payload, :dependencies_available?, true) do
          socket
          |> assign(:project_elm_direct, payload.direct)
          |> assign(:project_elm_indirect, payload.indirect)
        else
          socket
        end

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:refresh_editor_dependencies, {:exit, _reason}, socket) do
    {:noreply, socket}
  end

  def handle_async(:run_build, {:ok, {:ok, result}}, socket) do
    primary = result.primary

    socket =
      socket
      |> assign(:build_status, result.status)
      |> assign(:build_output, result.output)
      |> assign(:check_status, primary.check.status)
      |> assign(:check_output, primary.check.output)
      |> assign(:compile_status, primary.compile.status)
      |> assign(:compile_output, primary.compile.output)
      |> assign(:manifest_status, primary.manifest.status)
      |> assign(:manifest_output, primary.manifest.output)

    socket = DebuggerBridge.sync_check(socket, primary.check)
    socket = DebuggerBridge.sync_compile(socket, primary.compile)
    socket = DebuggerBridge.sync_manifest(socket, primary.manifest)
    {:noreply, socket}
  end

  def handle_async(:run_build, {:ok, {:error, reason}}, socket) do
    socket =
      socket
      |> assign(:build_status, :error)
      |> assign(:build_output, "Build failed before execution: #{inspect(reason)}")
      |> assign(:check_status, :error)
      |> assign(:compile_status, :error)
      |> assign(:manifest_status, :error)

    socket = DebuggerBridge.sync_check_failed(socket, inspect(reason))
    socket = DebuggerBridge.sync_compile_failed(socket, inspect(reason))
    socket = DebuggerBridge.sync_manifest_failed(socket, inspect(reason))
    {:noreply, socket}
  end

  def handle_async(:run_build, {:exit, reason}, socket) do
    socket =
      socket
      |> assign(:build_status, :error)
      |> assign(:build_output, "Build task exited: #{inspect(reason)}")
      |> assign(:check_status, :error)
      |> assign(:compile_status, :error)
      |> assign(:manifest_status, :error)

    socket = DebuggerBridge.sync_check_failed(socket, inspect(reason))
    socket = DebuggerBridge.sync_compile_failed(socket, inspect(reason))
    socket = DebuggerBridge.sync_manifest_failed(socket, inspect(reason))
    {:noreply, socket}
  end

  def handle_async(:run_compile, {:ok, {:ok, result}}, socket) do
    socket =
      socket
      |> assign(:compile_status, result.status)
      |> assign(:compile_output, result.output)

    socket = DebuggerBridge.sync_compile(socket, result)
    {:noreply, socket}
  end

  def handle_async(:run_manifest, {:ok, {:ok, result}}, socket) do
    mode = if result[:strict?], do: "strict", else: "default"

    socket =
      socket
      |> assign(:manifest_status, result.status)
      |> assign(:manifest_output, "[manifest mode: #{mode}]\n#{result.output}")

    socket = DebuggerBridge.sync_manifest(socket, result)
    {:noreply, socket}
  end

  def handle_async(:run_compile, {:ok, {:error, reason}}, socket) do
    socket =
      socket
      |> assign(:compile_status, :error)
      |> assign(:compile_output, inspect(reason))

    socket = DebuggerBridge.sync_compile_failed(socket, inspect(reason))
    {:noreply, socket}
  end

  def handle_async(:run_compile, {:exit, reason}, socket) do
    socket =
      socket
      |> assign(:compile_status, :error)
      |> assign(:compile_output, "Compiler compile task exited: #{inspect(reason)}")

    socket = DebuggerBridge.sync_compile_failed(socket, inspect(reason))
    {:noreply, socket}
  end

  def handle_async(:run_manifest, {:ok, {:error, reason}}, socket) do
    socket =
      socket
      |> assign(:manifest_status, :error)
      |> assign(:manifest_output, inspect(reason))

    socket = DebuggerBridge.sync_manifest_failed(socket, inspect(reason))
    {:noreply, socket}
  end

  def handle_async(:run_manifest, {:exit, reason}, socket) do
    socket =
      socket
      |> assign(:manifest_status, :error)
      |> assign(:manifest_output, "Compiler manifest task exited: #{inspect(reason)}")

    socket = DebuggerBridge.sync_manifest_failed(socket, inspect(reason))
    {:noreply, socket}
  end

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
        to_form(project_settings_form_data(project), as: :project_settings)
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

  def handle_async(:run_check, {:ok, {:error, reason}}, socket) do
    msg = inspect(reason)

    socket =
      socket
      |> assign(:check_status, :error)
      |> assign(:check_output, msg)
      |> assign(:diagnostics, [
        %{
          severity: "error",
          source: "ide",
          message: "Compiler check crashed: #{msg}",
          file: nil,
          line: nil,
          column: nil
        }
      ])

    socket = DebuggerBridge.sync_check_failed(socket, msg)
    {:noreply, socket}
  end

  def handle_async(:run_check, {:exit, reason}, socket) do
    msg = inspect(reason)

    socket =
      socket
      |> assign(:check_status, :error)
      |> assign(:check_output, msg)
      |> assign(:diagnostics, [
        %{
          severity: "error",
          source: "ide",
          message: "Compiler check task exited: #{msg}",
          file: nil,
          line: nil,
          column: nil
        }
      ])

    socket = DebuggerBridge.sync_check_failed(socket, msg)
    {:noreply, socket}
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
      class="flex h-[calc(100vh-4rem)] w-full max-w-none flex-col p-4"
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

      <section
        :if={@pane == :debugger}
        class="flex min-h-0 flex-1 flex-col overflow-hidden rounded-lg border border-zinc-200 bg-white p-4 shadow-sm"
      >
        <div class="flex items-start justify-between gap-3">
          <div>
            <h2 class="text-base font-semibold">Debugger</h2>
            <p class="mt-1 text-sm text-zinc-600">
              Elm-style update timeline with selected watch/companion models and watch render output.
            </p>
          </div>
          <button
            type="button"
            phx-click="debugger-toggle-advanced"
            class="rounded bg-zinc-100 px-2 py-1 text-xs font-medium text-zinc-700 hover:bg-zinc-200"
          >
            {if @debugger_advanced_debug_tools, do: "Hide advanced tools", else: "Advanced tools"}
          </button>
        </div>
        <p :if={@debugger_state} class="mt-2 text-[11px] text-zinc-500">
          running: {to_string(@debugger_state.running)} · events: {length(@debugger_state.events)} · selected seq: {@debugger_cursor_seq ||
            "none"} · profile: {@debugger_state.watch_profile_id || "basalt"}
        </p>
        <div class="mt-3 flex flex-wrap items-center gap-2">
          <button
            type="button"
            phx-click="debugger-start"
            class="rounded bg-zinc-800 px-2 py-1 text-xs font-medium text-white hover:bg-zinc-700"
          >
            {if debugger_state_running?(@debugger_state), do: "Restart", else: "Start"}
          </button>
          <form class="flex items-center gap-1" phx-change="debugger-set-watch-profile">
            <label class="flex items-center gap-1 text-xs text-zinc-600">
              <span>Watch model</span>
              <select
                name="watch_profile_id"
                class="rounded border border-zinc-300 bg-white px-2 py-1 text-xs"
              >
                <option
                  :for={profile <- Ide.Debugger.watch_profiles()}
                  value={profile["id"]}
                  selected={
                    profile["id"] ==
                      selected_debugger_watch_profile_id(@debugger_state, @project)
                  }
                >
                  {profile["label"]}
                </option>
              </select>
            </label>
          </form>
        </div>
        <div class="mt-3 grid min-h-0 flex-1 grid-cols-12 gap-3">
          <div class="col-span-12 flex min-h-0 flex-col rounded border border-zinc-200 bg-zinc-50 p-2 lg:col-span-3">
            <div class="flex items-center justify-between gap-2">
              <h3 class="text-xs font-semibold uppercase tracking-wide text-zinc-600">Timeline</h3>
              <form phx-change="debugger-set-timeline-mode">
                <select
                  name="mode"
                  class="rounded border border-zinc-300 bg-white px-1.5 py-1 text-[11px] text-zinc-800"
                >
                  <option value="watch" selected={@debugger_timeline_mode == "watch"}>watch</option>
                  <option value="companion" selected={@debugger_timeline_mode == "companion"}>
                    companion
                  </option>
                  <option value="mixed" selected={@debugger_timeline_mode == "mixed"}>mixed</option>
                  <option value="separate" selected={@debugger_timeline_mode == "separate"}>
                    separate
                  </option>
                </select>
              </form>
            </div>
            <div
              :if={@debugger_timeline_mode != "separate"}
              class="mt-2 min-h-0 flex-1 overflow-auto rounded border border-zinc-200 bg-white"
            >
              <.debugger_debugger_timeline_rows
                rows={
                  DebuggerSupport.debugger_rows_for_mode(
                    @debugger_rows,
                    @debugger_timeline_mode
                  )
                }
                selected_row={@debugger_selected_row}
                empty_label="No update messages for this timeline view."
              />
            </div>
            <div
              :if={@debugger_timeline_mode == "separate"}
              class="mt-2 grid min-h-0 flex-1 grid-rows-2 gap-2"
            >
              <div class="min-h-0 overflow-auto rounded border border-zinc-200 bg-white">
                <p class="sticky top-0 border-b border-zinc-100 bg-zinc-50 px-2 py-1 text-[10px] font-semibold uppercase tracking-wide text-zinc-500">
                  Watch
                </p>
                <.debugger_debugger_timeline_rows
                  rows={DebuggerSupport.debugger_rows_for_target(@debugger_rows, "watch")}
                  selected_row={@debugger_selected_row}
                  empty_label="No watch update messages."
                />
              </div>
              <div class="min-h-0 overflow-auto rounded border border-zinc-200 bg-white">
                <p class="sticky top-0 border-b border-zinc-100 bg-zinc-50 px-2 py-1 text-[10px] font-semibold uppercase tracking-wide text-zinc-500">
                  Companion
                </p>
                <.debugger_debugger_timeline_rows
                  rows={DebuggerSupport.debugger_rows_for_target(@debugger_rows, "companion")}
                  selected_row={@debugger_selected_row}
                  empty_label="No companion update messages."
                />
              </div>
            </div>
          </div>
          <div class="col-span-12 grid min-h-0 grid-cols-2 gap-3 lg:col-span-4">
            <div class="flex min-h-0 flex-col rounded border border-zinc-200 bg-zinc-50 p-2">
              <h3 class="text-xs font-semibold uppercase tracking-wide text-zinc-600">Watch model</h3>
              <.debugger_model_tree runtime={@debugger_watch_runtime} />
              <.debugger_subscription_buttons
                title="Watch subscribed events"
                rows={@debugger_watch_trigger_buttons}
                target="watch"
                disabled_subscriptions={@debugger_disabled_subscriptions}
              />
            </div>
            <div class="flex min-h-0 flex-col rounded border border-zinc-200 bg-zinc-50 p-2">
              <h3 class="text-xs font-semibold uppercase tracking-wide text-zinc-600">
                Companion model
              </h3>
              <.debugger_model_tree runtime={@debugger_companion_runtime} />
              <.debugger_subscription_buttons
                title="Companion subscribed events"
                rows={@debugger_companion_trigger_buttons}
                target="protocol"
                disabled_subscriptions={@debugger_disabled_subscriptions}
              />
            </div>
          </div>
          <div class="col-span-12 grid min-h-0 grid-cols-2 gap-3 lg:col-span-5">
            <div class="flex min-h-0 flex-col rounded border border-zinc-200 bg-zinc-50 p-2">
              <h3 class="text-xs font-semibold uppercase tracking-wide text-zinc-600">
                Rendered view
              </h3>
              <.debugger_rendered_view_tree
                id="debugger-watch-rendered-view"
                runtime={@debugger_watch_view_runtime}
              />
            </div>
            <div class="h-full min-h-0">
              <.debugger_view_preview
                runtime={@debugger_watch_view_runtime}
                project={@project}
                title="Visual preview"
              />
            </div>
          </div>
        </div>
        <p
          :if={@debugger_advanced_debug_tools}
          class="mt-3 rounded border border-amber-100 bg-amber-50/80 px-2 py-1.5 text-xs text-amber-950"
        >
          Saving <span class="font-mono text-[11px]">.elm</span>
          from watch / protocol / phone parses
          with the IDE’s elmc frontend into <span class="font-medium">parser snapshots</span>
          of <span class="font-mono text-[11px]">init</span>
          (static tuple peel), <span class="font-mono text-[11px]">Msg</span>
          constructors, and a <span class="font-medium">view outline</span>
          replace the sample preview on that surface when the outline is non-empty (watch, companion for protocol, phone for phone). Elm is still
          <span class="font-medium">not executed</span>
          (<span class="font-mono text-[11px]">update</span> / runtime pixels are not live yet).
        </p>
        <.debugger_trigger_modal open={@debugger_trigger_modal_open} form={@debugger_trigger_form} />
        <div
          :if={@debugger_advanced_debug_tools}
          class="mt-4 overflow-auto border-t border-zinc-200 pt-4"
        >
          <h3 class="text-sm font-semibold">Controls</h3>
          <div class="mt-2 flex items-center gap-2">
            <.button phx-click="debugger-start" class="!bg-zinc-800 hover:!bg-zinc-700">
              {if debugger_state_running?(@debugger_state),
                do: "Restart debugger",
                else: "Start debugger"}
            </.button>
            <.button phx-click="debugger-tick" class="!bg-zinc-100 !text-zinc-800 hover:!bg-zinc-200">
              Inject tick
            </.button>
            <.button
              phx-click="debugger-auto-tick-start"
              class="!bg-zinc-100 !text-zinc-800 hover:!bg-zinc-200"
            >
              Start auto tick
            </.button>
            <.button
              phx-click="debugger-auto-tick-stop"
              class="!bg-zinc-100 !text-zinc-800 hover:!bg-zinc-200"
            >
              Stop auto tick
            </.button>
          </div>
          <form class="mt-2 flex flex-wrap items-end gap-2" phx-change="debugger-set-watch-profile">
            <label class="flex flex-col gap-1 text-xs text-zinc-600">
              <span>Watch model profile</span>
              <select
                name="watch_profile_id"
                class="rounded border border-zinc-300 bg-white px-2 py-1 text-xs"
              >
                <option
                  :for={profile <- Ide.Debugger.watch_profiles()}
                  value={profile["id"]}
                  selected={
                    profile["id"] ==
                      selected_debugger_watch_profile_id(@debugger_state, @project)
                  }
                >
                  {profile["label"]}
                </option>
              </select>
            </label>
          </form>
          <.form
            :if={@debugger_advanced_debug_tools}
            for={@debugger_export_form}
            id="debugger-export-trace-form"
            phx-submit="debugger-export-trace"
            class="mt-3 grid grid-cols-1 gap-2 rounded border border-zinc-200 bg-zinc-50 p-2 md:grid-cols-[1fr_1fr_auto]"
          >
            <input
              type="text"
              name="debugger_export[compare_cursor_seq]"
              value={@debugger_export_form[:compare_cursor_seq].value}
              placeholder={"compare cursor (blank = current #{if is_integer(@debugger_cursor_seq), do: @debugger_cursor_seq, else: "latest"})"}
              class="w-full rounded border border-zinc-300 bg-white px-2 py-1 text-[11px] text-zinc-900"
            />
            <input
              type="text"
              name="debugger_export[baseline_cursor_seq]"
              value={@debugger_export_form[:baseline_cursor_seq].value}
              placeholder={"baseline cursor (blank = preview #{if is_integer(@debugger_replay_preview_seq), do: @debugger_replay_preview_seq, else: "latest before current"})"}
              class="w-full rounded border border-zinc-300 bg-white px-2 py-1 text-[11px] text-zinc-900"
            />
            <.button type="submit" class="!bg-zinc-100 !text-zinc-800 hover:!bg-zinc-200">
              Export trace (JSON)
            </.button>
          </.form>
          <p class="mt-2 text-sm text-zinc-600">
            Tracks watch + companion runtime substrate with deterministic event sequencing.
          </p>
          <p :if={@debugger_state && @debugger_state.auto_tick} class="mt-1 text-[11px] text-zinc-500">
            auto tick: {if @debugger_state.auto_tick.enabled, do: "on", else: "off"} · interval {@debugger_state.auto_tick.interval_ms ||
              "—"}ms · target {@debugger_state.auto_tick.target || "all"}
          </p>
          <div
            :if={@debugger_advanced_debug_tools && @debugger_trace_export}
            class="mt-3 rounded border border-zinc-200 bg-zinc-50 p-2"
          >
            <p class="text-[11px] text-zinc-700">
              Deterministic export · sha256 {@debugger_trace_export.sha256} · {@debugger_trace_export.byte_size} bytes
            </p>
            <p
              :if={
                @debugger_trace_export_context &&
                  (is_integer(@debugger_trace_export_context.compare_cursor_seq) ||
                     is_integer(@debugger_trace_export_context.baseline_cursor_seq))
              }
              class="mt-1 text-[10px] text-zinc-500"
            >
              runtime compare anchors:
              current {@debugger_trace_export_context.compare_cursor_seq || "latest"} · baseline {@debugger_trace_export_context.baseline_cursor_seq ||
                "latest before current"}
            </p>
            <pre class="mt-2 max-h-48 overflow-auto rounded bg-zinc-900 p-2 text-[10px] text-zinc-100 select-all"><%= @debugger_trace_export.json %></pre>
          </div>

          <.form
            :if={@debugger_advanced_debug_tools}
            for={@debugger_import_form}
            id="debugger-import-trace-form"
            phx-submit="debugger-import-trace"
            class="mt-4 space-y-2 border-t border-zinc-200 pt-4"
          >
            <h3 class="text-sm font-semibold">Import / replay trace</h3>
            <p class="text-[11px] text-zinc-600">
              Paste JSON from <span class="font-medium">Export trace</span>. The trace’s
              <span class="font-mono">project_slug</span>
              must match this project.
            </p>
            <textarea
              name="debugger_import[json]"
              rows="5"
              class="w-full rounded border border-zinc-300 bg-white p-2 font-mono text-[11px] text-zinc-900"
              placeholder="Paste export JSON (export_version 1)"
            >{@debugger_import_form[:json].value}</textarea>
            <.button type="submit" class="!bg-zinc-800 hover:!bg-zinc-700">
              Import trace
            </.button>
          </.form>

          <.form
            for={@debugger_filter_form}
            phx-change="debugger-set-filters"
            class="mt-3 grid grid-cols-1 gap-2 md:grid-cols-2"
          >
            <.input
              field={@debugger_filter_form[:types]}
              type="text"
              label="Event types (comma-separated)"
              placeholder="debugger.update_in,debugger.protocol_tx"
            />
            <.input
              field={@debugger_filter_form[:since_seq]}
              type="text"
              label="Only events with seq >"
              placeholder="0"
            />
          </.form>

          <div :if={@debugger_state} class="mt-3 space-y-3 text-xs">
            <p class="rounded border border-zinc-200 bg-zinc-50 px-2 py-1">
              running: {to_string(@debugger_state.running)} · revision: {@debugger_state.revision ||
                "none"} ·
              events: {length(@debugger_state.events)} · cursor seq: {@debugger_cursor_seq || "none"} · profile: {@debugger_state.watch_profile_id ||
                "basalt"}
            </p>
            <div class="flex flex-wrap items-center gap-2">
              <.button
                phx-click="debugger-jump-latest"
                disabled={@debugger_state.events == []}
                class="!bg-zinc-800 hover:!bg-zinc-700"
              >
                Jump latest
              </.button>
              <.button
                phx-click="debugger-step-back"
                disabled={@debugger_state.events == []}
                class="!bg-zinc-100 !text-zinc-800 hover:!bg-zinc-200"
              >
                Step back
              </.button>
              <.button
                phx-click="debugger-step-forward"
                disabled={@debugger_state.events == []}
                class="!bg-zinc-100 !text-zinc-800 hover:!bg-zinc-200"
              >
                Step forward
              </.button>
              <.button
                phx-click="debugger-continue-from-cursor"
                disabled={@debugger_state.events == []}
                class="!bg-emerald-100 !text-emerald-900 hover:!bg-emerald-200"
              >
                Continue from cursor snapshot
              </.button>
              <span class="text-zinc-600">
                selected event type: {(@debugger_selected_event && @debugger_selected_event.type) ||
                  "none"}
              </span>
            </div>
            <div class="rounded border border-zinc-200 bg-zinc-50 p-2">
              <p class="mb-1 text-[11px] font-semibold text-zinc-700">
                Trigger injection (subscription/button triggers)
              </p>
              <div class="flex flex-wrap gap-1">
                <button
                  :for={row <- @debugger_trigger_buttons}
                  type="button"
                  phx-click="debugger-open-trigger-modal"
                  phx-value-trigger={row.trigger}
                  phx-value-target={row.target}
                  phx-value-message={row.message}
                  class="rounded bg-zinc-200 px-2 py-1 text-[11px] font-medium text-zinc-800 hover:bg-zinc-300"
                >
                  {row.label}
                </button>
              </div>
            </div>
            <p class="text-[11px] text-zinc-500">
              With Debugger selected: <kbd class="rounded bg-zinc-200 px-1">j</kbd>
              step to older event, <kbd class="rounded bg-zinc-200 px-1">k</kbd>
              step to newer, <kbd class="rounded bg-zinc-200 px-1">/</kbd>
              focus timeline search (not while typing in a field).
            </p>
            <.form
              :if={@debugger_advanced_debug_tools}
              for={@debugger_replay_form}
              phx-change="debugger-replay-change"
              phx-submit="debugger-replay-recent"
              class="grid grid-cols-1 gap-2 rounded border border-zinc-200 bg-zinc-50 p-2 md:grid-cols-5"
            >
              <label class="flex flex-col gap-1 text-[11px] text-zinc-700">
                <span>Replay count</span>
                <input
                  type="number"
                  name="debugger_replay[count]"
                  min="1"
                  max="50"
                  value={@debugger_replay_form[:count].value}
                  class="rounded border border-zinc-300 bg-white px-2 py-1 text-[11px]"
                />
              </label>
              <label class="flex flex-col gap-1 text-[11px] text-zinc-700">
                <span>Target</span>
                <select
                  name="debugger_replay[target]"
                  class="rounded border border-zinc-300 bg-white px-2 py-1 text-[11px]"
                >
                  <option value="all" selected={@debugger_replay_form[:target].value == "all"}>
                    all
                  </option>
                  <option value="watch" selected={@debugger_replay_form[:target].value == "watch"}>
                    watch
                  </option>
                  <option
                    value="companion"
                    selected={@debugger_replay_form[:target].value == "companion"}
                  >
                    companion
                  </option>
                  <option
                    value="protocol"
                    selected={@debugger_replay_form[:target].value == "protocol"}
                  >
                    protocol
                  </option>
                  <option value="phone" selected={@debugger_replay_form[:target].value == "phone"}>
                    phone
                  </option>
                </select>
              </label>
              <label class="flex items-center gap-2 text-[11px] text-zinc-700 md:pt-5">
                <input
                  type="checkbox"
                  name="debugger_replay[cursor_bound]"
                  value="true"
                  checked={@debugger_replay_form[:cursor_bound].value in ["true", true, "on", "1", 1]}
                />
                <span>Bound to cursor seq</span>
              </label>
              <label class="flex flex-col gap-1 text-[11px] text-zinc-700">
                <span>Replay mode</span>
                <select
                  name="debugger_replay[mode]"
                  class="rounded border border-zinc-300 bg-white px-2 py-1 text-[11px]"
                >
                  <option value="frozen" selected={@debugger_replay_form[:mode].value == "frozen"}>
                    frozen preview
                  </option>
                  <option value="live" selected={@debugger_replay_form[:mode].value == "live"}>
                    live query
                  </option>
                </select>
              </label>
              <div class="md:pt-4">
                <.button type="submit" class="!bg-zinc-100 !text-zinc-800 hover:!bg-zinc-200">
                  Replay recent
                </.button>
              </div>
            </.form>
            <p
              :if={@debugger_advanced_debug_tools && @debugger_replay_live_warning}
              class="text-[11px] text-amber-900"
            >
              Live replay warning: timeline advanced since last preview, so submit may replay different rows.
              <span
                :if={is_integer(@debugger_replay_live_drift)}
                class={[
                  "ml-1 rounded px-1",
                  case DebuggerSupport.replay_live_drift_severity(@debugger_replay_live_drift) do
                    :mild -> "bg-amber-100 text-amber-900"
                    :medium -> "bg-orange-100 text-orange-900"
                    :high -> "bg-rose-100 text-rose-900"
                    _ -> "bg-zinc-100 text-zinc-700"
                  end
                ]}
                title={
                  case DebuggerSupport.replay_live_drift_severity(@debugger_replay_live_drift) do
                    :mild -> "Mild drift: 1-3 seq"
                    :medium -> "Medium drift: 4-10 seq"
                    :high -> "High drift: 11+ seq"
                    _ -> "No drift"
                  end
                }
              >
                drift +{@debugger_replay_live_drift} seq
              </span>
              <button
                type="button"
                phx-click="debugger-replay-refresh-preview"
                class="ml-2 rounded bg-amber-100 px-1.5 py-0.5 text-[10px] font-medium text-amber-900 hover:bg-amber-200"
              >
                Refresh preview now
              </button>
              <span class="ml-2 text-[10px] text-zinc-600">
                [!] mild 1-3, [!!] medium 4-10, [!!!] high 11+
              </span>
            </p>
            <p
              :if={@debugger_advanced_debug_tools && is_integer(@debugger_replay_preview_seq)}
              class="text-[11px] text-zinc-500"
            >
              Preview baseline seq: {@debugger_replay_preview_seq}
            </p>
            <p :if={@debugger_advanced_debug_tools} class="text-[11px] text-zinc-600">
              Replay preview:
              <span :if={@debugger_replay_preview == []}> no matching update messages</span>
              <span :if={@debugger_replay_preview != []}>
                {@debugger_replay_preview
                |> Enum.map(fn row -> "##{row.seq} #{row.target}: #{row.message}" end)
                |> Enum.join(" | ")}
              </span>
            </p>
            <p
              :if={@debugger_advanced_debug_tools && @debugger_replay_compare}
              class="text-[11px] text-zinc-600"
            >
              Replay validator:
              <span
                :if={@debugger_replay_compare.status == :match}
                class="rounded bg-emerald-100 px-1 text-emerald-800"
              >
                matched
              </span>
              <span
                :if={@debugger_replay_compare.status == :mismatch}
                class="rounded bg-amber-100 px-1 text-amber-900"
              >
                diverged ({@debugger_replay_compare.reason})
              </span>
              <span
                :if={@debugger_replay_compare.status == :none}
                class="rounded bg-zinc-100 px-1 text-zinc-700"
              >
                no applied replay yet
              </span>
              · preview {@debugger_replay_compare.preview_count} · applied {@debugger_replay_compare.applied_count}
            </p>
            <p
              :if={
                @debugger_advanced_debug_tools &&
                  @debugger_replay_compare &&
                  @debugger_replay_compare.status == :mismatch &&
                  (@debugger_replay_compare.mismatch_preview ||
                     @debugger_replay_compare.mismatch_applied)
              }
              class="text-[11px] text-amber-900"
            >
              Mismatch detail:
              preview {case @debugger_replay_compare.mismatch_preview do
                nil ->
                  "(none)"

                row ->
                  "##{row.seq} #{row.target}: #{row.message}"
              end} vs applied {case @debugger_replay_compare.mismatch_applied do
                nil ->
                  "(none)"

                row ->
                  "##{row.seq} #{row.target}: #{row.message}"
              end}
            </p>
            <.form
              :if={@debugger_advanced_debug_tools}
              for={@debugger_compare_form}
              phx-change="debugger-set-compare-baseline"
              class="grid grid-cols-1 gap-2 rounded border border-zinc-200 bg-zinc-50 p-2 md:grid-cols-4"
            >
              <label class="flex flex-col gap-1 text-[11px] text-zinc-700">
                <span>Snapshot compare baseline seq</span>
                <input
                  type="text"
                  name="debugger_compare[baseline_seq]"
                  value={@debugger_compare_form[:baseline_seq].value}
                  placeholder="(blank disables compare)"
                  class="rounded border border-zinc-300 bg-white px-2 py-1 text-[11px]"
                />
              </label>
              <div class="flex items-end gap-2 pb-0.5">
                <button
                  type="button"
                  phx-click="debugger-use-preview-baseline"
                  class="rounded bg-zinc-200 px-2 py-1 text-[11px] font-medium text-zinc-800 hover:bg-zinc-300"
                >
                  Use replay preview seq
                </button>
              </div>
              <p class="col-span-full text-[11px] text-zinc-600">
                Snapshot compare baseline is independent from replay validation.
              </p>
            </.form>
            <p
              :if={@debugger_advanced_debug_tools && @debugger_runtime_fingerprint_compare}
              class="text-[11px] text-zinc-600"
            >
              Runtime fingerprint compare:
              <span class="font-mono">
                cursor {@debugger_runtime_fingerprint_compare.cursor_seq}
              </span>
              vs
              <span class="font-mono">
                baseline {@debugger_runtime_fingerprint_compare.compare_cursor_seq}
              </span>
              · changed surfaces {@debugger_runtime_fingerprint_compare.changed_surface_count} · backend drift surfaces {Map.get(
                @debugger_runtime_fingerprint_compare,
                :backend_changed_surface_count,
                0
              )} · key-target drift surfaces {Map.get(
                @debugger_runtime_fingerprint_compare,
                :key_target_changed_surface_count,
                0
              )}
              <span :if={map_size(@debugger_runtime_fingerprint_compare.surfaces || %{}) > 0}>
                ( {@debugger_runtime_fingerprint_compare.surfaces
                |> Enum.map(fn {surface, row} ->
                  status = if row[:changed], do: "changed", else: "same"
                  "#{surface}=#{status}"
                end)
                |> Enum.join(", ")} )
              </span>
              <span :if={
                Map.get(@debugger_runtime_fingerprint_compare, :backend_changed_surface_count, 0) > 0
              }>
                · backend detail {DebuggerSupport.backend_drift_detail(
                  @debugger_runtime_fingerprint_compare
                ) || "(none)"}
              </span>
              <span :if={
                Map.get(@debugger_runtime_fingerprint_compare, :key_target_changed_surface_count, 0) >
                  0
              }>
                · key-target detail {DebuggerSupport.key_target_drift_detail(
                  @debugger_runtime_fingerprint_compare
                ) || "(none)"}
              </span>
              <span :if={is_binary(Map.get(@debugger_runtime_fingerprint_compare, :drift_detail))}>
                · drift detail {Map.get(@debugger_runtime_fingerprint_compare, :drift_detail)}
              </span>
            </p>
            <p
              :if={@debugger_advanced_debug_tools && @debugger_last_replay}
              class="text-[11px] text-zinc-600"
            >
              Last applied replay:
              <span class="font-mono">
                seq #{@debugger_last_replay.seq}
              </span>
              · target {@debugger_last_replay.target || "all"} ·
              source {@debugger_last_replay.replay_source || "recent_query"} ·
              replayed {@debugger_last_replay.replayed_count || 0}/{@debugger_last_replay.requested_count ||
                0}
              <span :if={is_integer(@debugger_last_replay.cursor_seq)}>
                · cursor &lt;= {@debugger_last_replay.cursor_seq}
              </span>
              <span :if={@debugger_last_replay.replay_preview != []}>
                · rows {@debugger_last_replay.replay_preview
                |> Enum.map(fn row ->
                  seq = row[:seq] || row["seq"]
                  target = row[:target] || row["target"]
                  message = row[:message] || row["message"]
                  "##{seq} #{target}: #{message}"
                end)
                |> Enum.join(" | ")}
              </span>
            </p>
            <p
              :if={
                @debugger_advanced_debug_tools &&
                  @debugger_last_replay &&
                  map_size(@debugger_last_replay.replay_telemetry || %{}) > 0
              }
              class="text-[11px] text-zinc-500"
            >
              Replay telemetry: {case @debugger_last_replay.replay_telemetry do
                telemetry when is_map(telemetry) ->
                  mode = telemetry[:mode] || telemetry["mode"] || "unknown"
                  source = telemetry[:source] || telemetry["source"] || "unknown"
                  drift_band = telemetry[:drift_band] || telemetry["drift_band"] || "none"
                  "mode #{mode} · source #{source} · drift-band #{drift_band}"

                _ ->
                  "n/a"
              end}
            </p>
            <.form
              for={@debugger_timeline_form}
              phx-change="debugger-set-cursor"
              class="grid grid-cols-1 gap-2 md:grid-cols-2"
            >
              <.input
                field={@debugger_timeline_form[:seq]}
                type="text"
                label="Jump to seq"
                placeholder="1"
              />
              <label class="flex flex-col gap-1 text-[11px] font-medium text-zinc-700">
                <span>Timeline scrubber</span>
                <input
                  type="range"
                  name="debugger_timeline[range_seq]"
                  min={DebuggerSupport.min_seq(@debugger_state.events)}
                  max={DebuggerSupport.max_seq(@debugger_state.events)}
                  value={@debugger_cursor_seq || DebuggerSupport.min_seq(@debugger_state.events)}
                  disabled={@debugger_state.events == []}
                  class="w-full"
                />
              </label>
            </.form>
            <div class="flex flex-wrap items-center gap-2">
              <button
                type="button"
                phx-click="debugger-filter-type"
                phx-value-type="*"
                class="rounded bg-zinc-100 px-2 py-1 text-[11px] font-medium text-zinc-700 hover:bg-zinc-200"
              >
                all ({length(@debugger_state.events)})
              </button>
              <button
                :for={{type, count} <- DebuggerSupport.event_type_counts(@debugger_state.events)}
                type="button"
                phx-click="debugger-filter-type"
                phx-value-type={type}
                class={[
                  "rounded px-2 py-1 text-[11px] font-medium",
                  Enum.member?(@debugger_types, type) && "bg-zinc-800 text-zinc-100",
                  !Enum.member?(@debugger_types, type) &&
                    "bg-zinc-100 text-zinc-700 hover:bg-zinc-200"
                ]}
              >
                {type} ({count})
              </button>
            </div>
            <p class="rounded border border-zinc-200 bg-zinc-50 px-2 py-1 text-[11px] text-zinc-700">
              Live runtime tip (latest state)
            </p>
            <div class="grid grid-cols-1 gap-3 lg:grid-cols-2">
              <pre class="max-h-52 overflow-auto rounded bg-zinc-900 p-2 text-[11px] text-zinc-100"><%= DebuggerSupport.runtime_json(@debugger_state.watch) %></pre>
              <pre class="max-h-52 overflow-auto rounded bg-zinc-900 p-2 text-[11px] text-zinc-100"><%= DebuggerSupport.runtime_json(@debugger_state.companion) %></pre>
            </div>
            <div class="flex flex-wrap items-center gap-2">
              <button
                :for={kind <- ["all", "protocol", "update", "render", "lifecycle", "other"]}
                type="button"
                phx-click="debugger-set-timeline-kind"
                phx-value-kind={kind}
                class={[
                  "rounded px-2 py-1 text-[11px] font-medium",
                  Atom.to_string(@debugger_timeline_kind) == kind &&
                    "bg-zinc-800 text-zinc-100",
                  Atom.to_string(@debugger_timeline_kind) != kind &&
                    "bg-zinc-100 text-zinc-700 hover:bg-zinc-200"
                ]}
              >
                {kind}
              </button>
              <.form
                for={to_form(%{"limit" => @debugger_timeline_limit}, as: :timeline)}
                phx-change="debugger-set-timeline-limit"
              >
                <label class="flex items-center gap-2 text-[11px] text-zinc-700">
                  <span>Rows</span>
                  <select
                    name="timeline[limit]"
                    class="rounded border border-zinc-300 bg-white px-2 py-1 text-[11px]"
                  >
                    <option
                      :for={limit <- [10, 30, 100, 200]}
                      value={limit}
                      selected={limit == @debugger_timeline_limit}
                    >
                      {limit}
                    </option>
                  </select>
                </label>
              </.form>
              <.form
                for={to_form(%{"query" => @debugger_timeline_query}, as: :timeline)}
                phx-change="debugger-set-timeline-search"
              >
                <label class="flex items-center gap-2 text-[11px] text-zinc-700">
                  <span>Search</span>
                  <input
                    id="debugger-timeline-search"
                    type="text"
                    name="timeline[query]"
                    value={@debugger_timeline_query}
                    placeholder="type or message"
                    class="rounded border border-zinc-300 bg-white px-2 py-1 text-[11px]"
                  />
                </label>
              </.form>
            </div>
            <div class="overflow-x-auto rounded border border-zinc-200">
              <table class="min-w-full text-[11px]">
                <thead class="bg-zinc-50 text-zinc-600">
                  <tr>
                    <th class="px-2 py-1 text-left">Seq</th>
                    <th class="px-2 py-1 text-left">Type</th>
                    <th class="px-2 py-1 text-left">Target</th>
                    <th class="px-2 py-1 text-left">Message</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={
                      row <-
                        DebuggerSupport.filtered_event_summaries(
                          @debugger_state.events,
                          @debugger_timeline_kind,
                          @debugger_timeline_limit,
                          @debugger_timeline_query
                        )
                    }
                    phx-click="debugger-select-event"
                    phx-value-seq={row.seq}
                    class={[
                      "cursor-pointer border-t border-zinc-100",
                      @debugger_cursor_seq == row.seq && "bg-zinc-800 text-zinc-100",
                      @debugger_cursor_seq != row.seq && "hover:bg-zinc-50"
                    ]}
                  >
                    <td class="px-2 py-1 font-mono">#{row.seq}</td>
                    <td class="px-2 py-1">
                      <span
                        :for={
                          fragment <-
                            DebuggerSupport.highlight_fragments(row.type, @debugger_timeline_query)
                        }
                        class={fragment.match? && "rounded bg-yellow-200 px-0.5 text-zinc-900"}
                      >
                        {fragment.text}
                      </span>
                    </td>
                    <td class="px-2 py-1">{row.target || "-"}</td>
                    <td class="max-w-[20rem] px-2 py-1">
                      <div class="truncate">
                        <span
                          :for={
                            fragment <-
                              DebuggerSupport.highlight_fragments(
                                row.message || "-",
                                @debugger_timeline_query
                              )
                          }
                          class={fragment.match? && "rounded bg-yellow-200 px-0.5 text-zinc-900"}
                        >
                          {fragment.text}
                        </span>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <p class="rounded border border-zinc-200 bg-zinc-50 px-2 py-1 text-[11px] text-zinc-700">
              Update messages (simulated <span class="font-mono">update</span>
              pipeline, through selected seq)
            </p>
            <div class="overflow-x-auto rounded border border-zinc-200">
              <table class="min-w-full text-[11px]">
                <thead class="bg-zinc-50 text-zinc-600">
                  <tr>
                    <th class="px-2 py-1 text-left">Seq</th>
                    <th class="px-2 py-1 text-left">Target</th>
                    <th class="px-2 py-1 text-left">Message</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={
                      row <-
                        DebuggerSupport.update_messages_at_cursor(
                          @debugger_state.events,
                          @debugger_cursor_seq,
                          40
                        )
                    }
                    phx-click="debugger-select-event"
                    phx-value-seq={row.seq}
                    class={[
                      "cursor-pointer border-t border-zinc-100",
                      @debugger_cursor_seq == row.seq && "bg-zinc-800 text-zinc-100",
                      @debugger_cursor_seq != row.seq && "hover:bg-zinc-50"
                    ]}
                  >
                    <td class="px-2 py-1 font-mono">#{row.seq}</td>
                    <td class="px-2 py-1">{row.target || "—"}</td>
                    <td class="max-w-[28rem] truncate px-2 py-1">{row.message || "—"}</td>
                  </tr>
                </tbody>
              </table>
            </div>
            <p class="rounded border border-zinc-200 bg-zinc-50 px-2 py-1 text-[11px] text-zinc-700">
              Protocol exchange (watch ↔ companion, through selected seq)
            </p>
            <div class="overflow-x-auto rounded border border-zinc-200">
              <table class="min-w-full text-[11px]">
                <thead class="bg-zinc-50 text-zinc-600">
                  <tr>
                    <th class="px-2 py-1 text-left">Seq</th>
                    <th class="px-2 py-1 text-left">Dir</th>
                    <th class="px-2 py-1 text-left">From</th>
                    <th class="px-2 py-1 text-left">To</th>
                    <th class="px-2 py-1 text-left">Message</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={
                      row <-
                        DebuggerSupport.protocol_exchange_at_cursor(
                          @debugger_state.events,
                          @debugger_cursor_seq,
                          40
                        )
                    }
                    phx-click="debugger-select-event"
                    phx-value-seq={row.seq}
                    class={[
                      "cursor-pointer border-t border-zinc-100",
                      @debugger_cursor_seq == row.seq && "bg-zinc-800 text-zinc-100",
                      @debugger_cursor_seq != row.seq && "hover:bg-zinc-50"
                    ]}
                  >
                    <td class="px-2 py-1 font-mono">#{row.seq}</td>
                    <td class="px-2 py-1 font-mono">{row.kind}</td>
                    <td class="px-2 py-1">{row.from || "—"}</td>
                    <td class="px-2 py-1">{row.to || "—"}</td>
                    <td class="max-w-[24rem] truncate px-2 py-1">{row.message || "—"}</td>
                  </tr>
                </tbody>
              </table>
            </div>
            <div class="grid grid-cols-1 gap-3 lg:grid-cols-2">
              <% debugger_render_rows =
                DebuggerSupport.render_events_at_cursor(
                  @debugger_state.events,
                  @debugger_cursor_seq,
                  24
                ) %>
              <% debugger_lifecycle_rows =
                DebuggerSupport.lifecycle_events_at_cursor(
                  @debugger_state.events,
                  @debugger_cursor_seq,
                  12
                ) %>
              <div>
                <p class="rounded border border-zinc-200 bg-zinc-50 px-2 py-1 text-[11px] text-zinc-700">
                  View renders (through selected seq)
                </p>
                <div class="overflow-x-auto rounded border border-zinc-200">
                  <table class="min-w-full text-[11px]">
                    <thead class="bg-zinc-50 text-zinc-600">
                      <tr>
                        <th class="px-2 py-1 text-left">Seq</th>
                        <th class="px-2 py-1 text-left">Target</th>
                        <th class="px-2 py-1 text-left">Root</th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= if debugger_render_rows == [] do %>
                        <tr class="border-t border-zinc-100">
                          <td class="px-2 py-2 text-zinc-500 italic" colspan="3">
                            No view renders through this point. Reload or step forward to record
                            <span class="font-mono not-italic">debugger.view_render</span>
                            events.
                          </td>
                        </tr>
                      <% else %>
                        <tr
                          :for={row <- debugger_render_rows}
                          phx-click="debugger-select-event"
                          phx-value-seq={row.seq}
                          class={[
                            "cursor-pointer border-t border-zinc-100",
                            @debugger_cursor_seq == row.seq && "bg-zinc-800 text-zinc-100",
                            @debugger_cursor_seq != row.seq && "hover:bg-zinc-50"
                          ]}
                        >
                          <td class="px-2 py-1 font-mono">#{row.seq}</td>
                          <td class="px-2 py-1">{row.target || "—"}</td>
                          <td class="max-w-[16rem] truncate px-2 py-1 font-mono">
                            {row.root || "—"}
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              </div>
              <div>
                <p class="rounded border border-zinc-200 bg-zinc-50 px-2 py-1 text-[11px] text-zinc-700">
                  Lifecycle (start / reset / reload / elm_introspect / elmc check / compile / manifest)
                </p>
                <div class="overflow-x-auto rounded border border-zinc-200">
                  <table class="min-w-full text-[11px]">
                    <thead class="bg-zinc-50 text-zinc-600">
                      <tr>
                        <th class="px-2 py-1 text-left">Seq</th>
                        <th class="px-2 py-1 text-left">Type</th>
                        <th class="px-2 py-1 text-left">Summary</th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= if debugger_lifecycle_rows == [] do %>
                        <tr class="border-t border-zinc-100">
                          <td class="px-2 py-2 text-zinc-500 italic" colspan="3">
                            No lifecycle events through this point. Start the debugger or move the
                            cursor past <span class="font-mono not-italic">debugger.start</span>.
                          </td>
                        </tr>
                      <% else %>
                        <tr
                          :for={row <- debugger_lifecycle_rows}
                          phx-click="debugger-select-event"
                          phx-value-seq={row.seq}
                          class={[
                            "cursor-pointer border-t border-zinc-100",
                            @debugger_cursor_seq == row.seq && "bg-zinc-800 text-zinc-100",
                            @debugger_cursor_seq != row.seq && "hover:bg-zinc-50"
                          ]}
                        >
                          <td class="px-2 py-1 font-mono">#{row.seq}</td>
                          <td class="px-2 py-1 font-mono">{row.type}</td>
                          <td class="max-w-[20rem] truncate px-2 py-1">{row.summary}</td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
            <p class="rounded border border-zinc-200 bg-zinc-50 px-2 py-1 text-[11px] text-zinc-700">
              Cursor runtime snapshot (frozen at selected seq)
            </p>
            <div class="grid grid-cols-1 gap-3 lg:grid-cols-2">
              <pre class="max-h-44 overflow-auto rounded border border-zinc-200 bg-zinc-50 p-2 text-[11px] text-zinc-900"><%= DebuggerSupport.runtime_json(@debugger_cursor_watch_runtime) %></pre>
              <pre class="max-h-44 overflow-auto rounded border border-zinc-200 bg-zinc-50 p-2 text-[11px] text-zinc-900"><%= DebuggerSupport.runtime_json(@debugger_cursor_companion_runtime) %></pre>
            </div>
            <p class="rounded border border-zinc-200 bg-zinc-50 px-2 py-1 text-[11px] text-zinc-700">
              Parser snapshot summary (static elmc parse, at cursor)
            </p>
            <div class="grid grid-cols-1 gap-3 lg:grid-cols-2">
              <pre class="max-h-36 overflow-auto whitespace-pre-wrap rounded border border-emerald-100 bg-emerald-50/80 p-2 font-mono text-[11px] text-emerald-950"><%= DebuggerSupport.format_elm_introspect_brief(@debugger_cursor_watch_runtime) %></pre>
              <pre class="max-h-36 overflow-auto whitespace-pre-wrap rounded border border-emerald-100 bg-emerald-50/80 p-2 font-mono text-[11px] text-emerald-950"><%= DebuggerSupport.format_elm_introspect_brief(@debugger_cursor_companion_runtime) %></pre>
            </div>
            <% debugger_diag =
              DebuggerSupport.diagnostics_preview_at_cursor(
                @debugger_state.events,
                @debugger_cursor_seq
              ) %>
            <% debugger_elmc_diag_rows_list = debugger_diag.rows %>
            <% debugger_elmc_diag_label =
              DebuggerSupport.diagnostics_preview_source_label(debugger_diag.source) %>
            <div
              :if={debugger_elmc_diag_rows_list != []}
              class="mt-3 rounded-lg border border-zinc-200 bg-white p-2 shadow-sm"
            >
              <p class="mb-1 text-[11px] font-semibold text-zinc-700">
                Elmc diagnostics · {debugger_elmc_diag_label}
              </p>
              <.debugger_elmc_diagnostic_preview rows={debugger_elmc_diag_rows_list} />
            </div>
            <div class="grid grid-cols-1 gap-3 lg:grid-cols-2">
              <div>
                <p class="rounded border border-zinc-200 bg-zinc-50 px-2 py-1 text-[11px] text-zinc-700">
                  Rendered view (watch, at cursor)
                </p>
                <.debugger_rendered_view_tree
                  id="debugger-watch-rendered-view"
                  runtime={@debugger_cursor_watch_runtime}
                />
              </div>
              <div>
                <p class="rounded border border-zinc-200 bg-zinc-50 px-2 py-1 text-[11px] text-zinc-700">
                  Rendered view (companion / phone app, at cursor)
                </p>
                <.debugger_rendered_view_tree
                  id="debugger-companion-rendered-view"
                  runtime={@debugger_cursor_companion_runtime}
                />
              </div>
            </div>
            <div class="grid grid-cols-1 gap-3 lg:grid-cols-2">
              <.debugger_view_preview
                runtime={@debugger_cursor_watch_runtime}
                project={@project}
                title="Watch · visual preview"
              />
              <.debugger_view_preview
                runtime={@debugger_cursor_companion_runtime}
                project={@project}
                title="Companion / phone app · visual preview"
              />
            </div>
            <pre class="max-h-44 overflow-auto rounded border border-zinc-200 bg-zinc-50 p-2 text-[11px] text-zinc-900"><%= DebuggerSupport.event_json(@debugger_selected_event) %></pre>
            <div class="grid grid-cols-1 gap-2 lg:grid-cols-2">
              <p class="rounded border border-zinc-200 bg-zinc-50 px-2 py-1 text-[11px] text-zinc-700">
                newer event: {(@debugger_newer_event && @debugger_newer_event.seq) || "none"} ·
                type: {(@debugger_newer_event && @debugger_newer_event.type) || "none"}
              </p>
              <p class="rounded border border-zinc-200 bg-zinc-50 px-2 py-1 text-[11px] text-zinc-700">
                older event: {(@debugger_older_event && @debugger_older_event.seq) || "none"} ·
                type: {(@debugger_older_event && @debugger_older_event.type) || "none"}
              </p>
            </div>
            <pre class="max-h-44 overflow-auto rounded border border-zinc-200 bg-zinc-50 p-2 text-[11px] text-zinc-900"><%= DebuggerSupport.payload_diff_json(@debugger_older_event, @debugger_selected_event) %></pre>
            <div class="rounded border border-zinc-200 bg-white p-2">
              <p class="mb-2 text-[11px] font-semibold uppercase tracking-wide text-zinc-600">
                Recent timeline events (click to inspect)
              </p>
              <div class="max-h-40 overflow-auto">
                <button
                  :for={event <- Enum.take(@debugger_state.events, 30)}
                  type="button"
                  phx-click="debugger-select-event"
                  phx-value-seq={event.seq}
                  class={[
                    "mb-1 w-full rounded px-2 py-1 text-left text-[11px]",
                    @debugger_cursor_seq == event.seq &&
                      "bg-zinc-800 text-zinc-100",
                    @debugger_cursor_seq != event.seq &&
                      "bg-zinc-100 text-zinc-700 hover:bg-zinc-200"
                  ]}
                >
                  #{event.seq} · {event.type}
                </button>
              </div>
            </div>
            <pre class="max-h-52 overflow-auto rounded bg-zinc-900 p-2 text-[11px] text-zinc-100"><%= DebuggerSupport.event_json(@debugger_state.events) %></pre>
          </div>
        </div>
      </section>

      {EmulatorPage.render(assigns)}
    </div>
    """
  end

  attr(:rows, :list, required: true)

  @spec debugger_elmc_diagnostic_preview(term()) :: term()
  defp debugger_elmc_diagnostic_preview(assigns) do
    ~H"""
    <div class="max-h-40 overflow-auto rounded border border-zinc-100">
      <table class="min-w-full text-[10px] text-zinc-800">
        <thead class="sticky top-0 bg-zinc-50 text-zinc-600">
          <tr>
            <th class="px-1.5 py-0.5 text-left font-medium">Sev</th>
            <th class="px-1.5 py-0.5 text-left font-medium">Src</th>
            <th class="px-1.5 py-0.5 text-left font-medium">Where</th>
            <th class="px-1.5 py-0.5 text-left font-medium">Message</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @rows} class="border-t border-zinc-100 align-top">
            <td class="px-1.5 py-0.5 font-mono text-zinc-700">
              {debugger_diag_field(row, "severity")}
            </td>
            <td class="px-1.5 py-0.5 font-mono text-zinc-600">
              {debugger_diag_field(row, "source")}
            </td>
            <td class="max-w-[10rem] truncate px-1.5 py-0.5 font-mono text-zinc-600">
              {debugger_diag_where(row)}
            </td>
            <td class="max-w-[28rem] truncate px-1.5 py-0.5 text-zinc-800">
              {debugger_diag_field(row, "message")}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr(:rows, :list, required: true)
  attr(:selected_row, :any, default: nil)
  attr(:empty_label, :string, default: "No update messages.")

  @spec debugger_debugger_timeline_rows(term()) :: term()
  defp debugger_debugger_timeline_rows(assigns) do
    ~H"""
    <button
      :for={row <- @rows}
      type="button"
      phx-click="debugger-select-debugger-event"
      phx-value-seq={row.seq}
      class={debugger_debugger_timeline_row_class(row, @selected_row)}
    >
      <span class="font-mono text-zinc-500">#{row.seq}</span>
      <span class="ml-1 rounded bg-zinc-100 px-1 font-medium text-zinc-700">
        {row.target}
      </span>
      <span class="ml-1 font-mono text-zinc-900">
        {DebuggerSupport.debugger_message_label(row.message)}
      </span>
    </button>
    <p :if={@rows == []} class="p-2 text-xs text-zinc-500">
      {@empty_label}
    </p>
    """
  end

  @spec debugger_debugger_timeline_row_class(term(), term()) :: [String.t() | boolean()]
  defp debugger_debugger_timeline_row_class(row, selected_row) do
    selected? =
      is_map(row) and is_map(selected_row) and
        Map.get(row, :seq) == Map.get(selected_row, :seq)

    target = if is_map(row), do: Map.get(row, :target), else: nil

    target_class =
      case target do
        "watch" -> "bg-sky-50 hover:bg-sky-100"
        "companion" -> "bg-emerald-50 hover:bg-emerald-100"
        _ -> "bg-white hover:bg-blue-50"
      end

    [
      "block w-full border-b border-zinc-100 px-2 py-1.5 text-left text-[11px]",
      target_class,
      selected? && "bg-blue-100 text-blue-950 ring-1 ring-inset ring-blue-300"
    ]
  end

  attr(:runtime, :any, required: true)

  @spec debugger_model_tree(term()) :: term()
  defp debugger_model_tree(assigns) do
    model = debugger_debugger_model(assigns.runtime)
    assigns = assign(assigns, :model, model)

    ~H"""
    <div class="mt-2 min-h-0 flex-1 overflow-auto rounded border border-zinc-200 bg-white p-2 font-mono text-[11px] text-zinc-900">
      <.debugger_model_node
        :if={is_map(@model) && map_size(@model) > 0}
        label="model"
        value={@model}
        depth={0}
      />
      <p :if={!is_map(@model) || map_size(@model) == 0} class="text-zinc-500">(no runtime model)</p>
    </div>
    """
  end

  attr(:label, :string, required: true)
  attr(:value, :any, required: true)
  attr(:depth, :integer, default: 0)

  @spec debugger_model_node(term()) :: term()
  defp debugger_model_node(assigns) do
    children = debugger_model_children(assigns.value)
    scalar = debugger_model_scalar(assigns.value)

    assigns =
      assigns
      |> assign(:children, children)
      |> assign(:scalar, scalar)
      |> assign(:tooltip, debugger_model_tooltip(assigns.label, assigns.value, children, scalar))
      |> assign(:open, assigns.depth < 2)

    ~H"""
    <div class="pl-1">
      <details :if={@children != []} open={@open} class="mt-0.5">
        <summary class="cursor-pointer select-none text-zinc-800" title={@tooltip}>
          <span class="font-semibold">{@label}</span>
          <span class="text-zinc-500">{debugger_model_container_label(@value)}</span>
        </summary>
        <div class="ml-3 border-l border-zinc-200 pl-2">
          <.debugger_model_node
            :for={child <- @children}
            label={child.label}
            value={child.value}
            depth={@depth + 1}
          />
        </div>
      </details>
      <div :if={@children == []} class="mt-0.5 truncate" title={@tooltip}>
        <span class="font-semibold text-zinc-800">{@label}</span>
        <span class="text-zinc-500"> = </span>
        <span class="text-zinc-700">{@scalar}</span>
      </div>
    </div>
    """
  end

  @spec debugger_model_children(term()) :: [%{label: String.t(), value: term()}]
  defp debugger_model_children(value) when is_map(value) do
    if debugger_model_elm_constructor?(value) do
      []
    else
      value
      |> Enum.map(fn {key, child_value} -> %{label: to_string(key), value: child_value} end)
      |> Enum.sort_by(& &1.label)
    end
  end

  defp debugger_model_children(value) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.map(fn {child_value, index} -> %{label: "[#{index}]", value: child_value} end)
  end

  defp debugger_model_children(_value), do: []

  @spec debugger_model_tooltip(String.t(), term(), [map()], String.t()) :: String.t()
  defp debugger_model_tooltip(label, _value, [], scalar)
       when is_binary(label) and is_binary(scalar),
       do: "#{label} = #{scalar}"

  defp debugger_model_tooltip(label, value, _children, _scalar) when is_binary(label) do
    "#{label} #{debugger_model_container_label(value)}"
  end

  @spec debugger_model_scalar(term()) :: String.t()
  defp debugger_model_scalar(value) when is_map(value) do
    if debugger_model_elm_constructor?(value),
      do: debugger_model_elm_value(value),
      else: inspect(value)
  end

  defp debugger_model_scalar(nil), do: "null"
  defp debugger_model_scalar(value) when is_binary(value), do: inspect(value)
  defp debugger_model_scalar(value) when is_boolean(value), do: to_string(value)
  defp debugger_model_scalar(value) when is_number(value), do: to_string(value)
  defp debugger_model_scalar(value) when is_atom(value), do: Atom.to_string(value)
  defp debugger_model_scalar(value), do: inspect(value)

  @spec debugger_model_container_label(term()) :: String.t()
  defp debugger_model_container_label(value) when is_map(value) do
    if debugger_model_elm_constructor?(value),
      do: debugger_model_elm_value(value),
      else: "{#{map_size(value)}}"
  end

  defp debugger_model_container_label(value) when is_list(value), do: "[#{length(value)}]"
  defp debugger_model_container_label(_value), do: ""

  @spec debugger_model_elm_constructor?(term()) :: boolean()
  defp debugger_model_elm_constructor?(value) when is_map(value) do
    ctor = Map.get(value, "ctor") || Map.get(value, "$ctor") || Map.get(value, :ctor)
    args = Map.get(value, "args") || Map.get(value, "$args") || Map.get(value, :args) || []

    is_binary(ctor) and is_list(args) and
      value
      |> Map.keys()
      |> Enum.all?(&(to_string(&1) in ["ctor", "args", "$ctor", "$args"]))
  end

  defp debugger_model_elm_constructor?(_value), do: false

  @spec debugger_model_elm_value(term()) :: String.t()
  defp debugger_model_elm_value(%{} = value) do
    ctor = Map.get(value, "ctor") || Map.get(value, "$ctor") || Map.get(value, :ctor)
    args = Map.get(value, "args") || Map.get(value, "$args") || Map.get(value, :args) || []

    case {ctor, args} do
      {ctor, []} when is_binary(ctor) ->
        ctor

      {ctor, args} when is_binary(ctor) and is_list(args) ->
        rendered_args =
          args
          |> Enum.map(&debugger_model_elm_arg_value/1)
          |> Enum.join(" ")

        String.trim("#{ctor} #{rendered_args}")

      _ ->
        inspect(value)
    end
  end

  defp debugger_model_elm_value(value), do: debugger_model_scalar(value)

  @spec debugger_model_elm_arg_value(term()) :: String.t()
  defp debugger_model_elm_arg_value(%{} = value) do
    if debugger_model_elm_constructor?(value) do
      rendered = debugger_model_elm_value(value)

      if constructor_arg_count(value) > 0 do
        "(" <> rendered <> ")"
      else
        rendered
      end
    else
      debugger_model_elm_record_value(value)
    end
  end

  defp debugger_model_elm_arg_value(value) when is_list(value) do
    inner =
      value
      |> Enum.map(&debugger_model_elm_arg_value/1)
      |> Enum.join(", ")

    "[" <> inner <> "]"
  end

  defp debugger_model_elm_arg_value(value) when is_boolean(value),
    do: if(value, do: "True", else: "False")

  defp debugger_model_elm_arg_value(value), do: debugger_model_scalar(value)

  @spec debugger_model_elm_record_value(map()) :: String.t()
  defp debugger_model_elm_record_value(value) when is_map(value) do
    inner =
      value
      |> Enum.map(fn {key, child_value} ->
        "#{key} = #{debugger_model_elm_arg_value(child_value)}"
      end)
      |> Enum.sort()
      |> Enum.join(", ")

    "{ " <> inner <> " }"
  end

  @spec constructor_arg_count(term()) :: non_neg_integer()
  defp constructor_arg_count(%{} = value) do
    args = Map.get(value, "args") || Map.get(value, "$args") || Map.get(value, :args) || []
    if is_list(args), do: length(args), else: 0
  end

  defp constructor_arg_count(_value), do: 0

  @spec debugger_debugger_model(term()) :: map()
  defp debugger_debugger_model(runtime) do
    runtime
    |> debugger_runtime_model()
    |> hide_debugger_model_metadata()
  end

  @spec hide_debugger_model_metadata(term()) :: map()
  defp hide_debugger_model_metadata(model) when is_map(model) do
    atom_keys = Enum.map(@debugger_model_metadata_keys, &String.to_atom/1)
    Map.drop(model, @debugger_model_metadata_keys ++ atom_keys)
  end

  defp hide_debugger_model_metadata(_model), do: %{}

  attr(:open, :boolean, required: true)
  attr(:form, :any, required: true)

  defp debugger_trigger_modal(assigns) do
    ~H"""
    <div :if={@open} class="fixed inset-0 z-50 grid place-items-center p-4">
      <div class="absolute inset-0 bg-black/40" phx-click="debugger-close-trigger-modal"></div>
      <div class="relative z-10 w-full max-w-md rounded-lg bg-white p-4 shadow-xl">
        <h3 class="text-sm font-semibold">Fire subscribed event</h3>
        <p class="mt-1 text-xs text-zinc-500">
          Review the message payload before injecting it into the debugger.
        </p>
        <.form for={@form} phx-submit="debugger-submit-trigger" class="mt-3 space-y-3">
          <input type="hidden" name="debugger_trigger[target]" value={@form[:target].value} />
          <input type="hidden" name="debugger_trigger[trigger]" value={@form[:trigger].value} />
          <input
            type="hidden"
            name="debugger_trigger[payload_kind]"
            value={@form[:payload_kind].value}
          />
          <input
            type="hidden"
            name="debugger_trigger[message_constructor]"
            value={@form[:message_constructor].value}
          />
          <label class="flex flex-col gap-1 text-xs text-zinc-600">
            <span>Trigger</span>
            <input
              type="text"
              value={@form[:trigger].value}
              readonly
              class="rounded border border-zinc-200 bg-zinc-50 px-2 py-1 font-mono text-[11px]"
            />
          </label>
          <.input
            :if={@form[:payload_kind].value == "message"}
            field={@form[:message]}
            type="text"
            label="Message"
            placeholder="Tick"
          />
          <.input
            :if={@form[:payload_kind].value == "integer"}
            field={@form[:payload]}
            type="number"
            label="Value"
          />
          <.input
            :if={@form[:payload_kind].value == "boolean"}
            field={@form[:payload]}
            type="select"
            label="Value"
            options={[{"True", "True"}, {"False", "False"}]}
          />
          <label
            :if={@form[:payload_kind].value == "none"}
            class="flex flex-col gap-1 text-xs text-zinc-600"
          >
            <span>Message</span>
            <input
              type="text"
              value={@form[:message].value}
              readonly
              class="rounded border border-zinc-200 bg-zinc-50 px-2 py-1 font-mono text-[11px]"
            />
          </label>
          <p class="text-[11px] text-zinc-500">
            Time subscriptions use the current local clock. System subscriptions use editable simulated values.
          </p>
          <div class="flex justify-end gap-2 pt-2">
            <button
              type="button"
              phx-click="debugger-close-trigger-modal"
              class="rounded px-3 py-2 text-xs text-zinc-600"
            >
              Cancel
            </button>
            <button
              type="submit"
              class="rounded bg-zinc-900 px-3 py-2 text-xs font-medium text-white hover:bg-zinc-800"
            >
              Fire event
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  attr(:title, :string, required: true)
  attr(:rows, :list, required: true)
  attr(:target, :string, required: true)
  attr(:disabled_subscriptions, :list, default: [])

  @spec debugger_subscription_buttons(term()) :: term()
  defp debugger_subscription_buttons(assigns) do
    ~H"""
    <div class="mt-2 shrink-0 rounded border border-zinc-200 bg-white p-2">
      <p class="text-[11px] font-semibold text-zinc-700">{@title}</p>
      <div class="mt-1 flex flex-wrap gap-1">
        <div :for={row <- @rows} class="inline-flex items-center gap-1 rounded bg-zinc-100 px-1 py-1">
          <form phx-change="debugger-set-subscription-enabled" class="flex items-center">
            <input type="hidden" name="target" value={@target} />
            <input type="hidden" name="trigger" value={row.trigger} />
            <input type="hidden" name="enabled" value="false" />
            <input
              type="checkbox"
              name="enabled"
              value="true"
              checked={subscription_trigger_enabled?(@disabled_subscriptions, @target, row.trigger)}
              class="rounded border-zinc-300"
              title="Enable this subscribed event"
            />
          </form>
          <button
            type="button"
            phx-click="debugger-open-trigger-modal"
            phx-value-trigger={row.trigger}
            phx-value-target={row.target}
            phx-value-message={row.message}
            disabled={
              not subscription_trigger_enabled?(@disabled_subscriptions, @target, row.trigger)
            }
            class="rounded bg-zinc-200 px-2 py-1 text-[10px] font-medium text-zinc-800 hover:bg-zinc-300 disabled:cursor-not-allowed disabled:opacity-50"
          >
            {row.label}
          </button>
        </div>
        <span :if={@rows == []} class="text-[11px] text-zinc-500">
          No parsed subscriptions for this app.
        </span>
      </div>
    </div>
    """
  end

  defp subscription_trigger_enabled?(disabled_subscriptions, target, trigger)
       when is_list(disabled_subscriptions) and is_binary(target) and is_binary(trigger) do
    not Enum.any?(disabled_subscriptions, fn row ->
      row_target = Map.get(row, "target") || Map.get(row, :target)
      row_trigger = Map.get(row, "trigger") || Map.get(row, :trigger)
      row_target == debugger_auto_fire_target(target) and row_trigger == trigger
    end)
  end

  defp subscription_trigger_enabled?(_disabled_subscriptions, _target, _trigger), do: true

  attr(:runtime, :any, required: true)
  attr(:project, :any, default: nil)
  attr(:title, :string, default: "Visual preview")

  @spec debugger_view_preview(term()) :: term()
  defp debugger_view_preview(assigns) do
    tree = debugger_preview_tree(assigns.runtime)
    {screen_w, screen_h} = debugger_preview_dimensions(assigns.runtime, tree)

    svg_ops =
      tree
      |> debugger_watch_svg_ops(assigns.runtime)
      |> hydrate_bitmap_svg_ops(assigns.project)

    unresolved_ops = Enum.filter(svg_ops, &(&1.kind == :unresolved))

    assigns =
      assigns
      |> assign(:tree, tree)
      |> assign(:screen_w, screen_w)
      |> assign(:screen_h, screen_h)
      |> assign(:svg_ops, svg_ops)
      |> assign(:unresolved_ops, unresolved_ops)

    ~H"""
    <div class="flex h-full min-h-0 flex-col rounded-lg border border-dashed border-zinc-300 bg-zinc-50/80 p-3">
      <p class="mb-2 shrink-0 text-[11px] font-semibold uppercase tracking-wide text-zinc-600">
        {@title}
      </p>
      <div class="mb-2 shrink-0 rounded border border-zinc-200 bg-zinc-100 p-2">
        <svg
          viewBox={"0 0 #{@screen_w} #{@screen_h}"}
          role="img"
          aria-label="Watch screen preview"
          class="mx-auto h-52 w-[11.25rem] rounded border border-zinc-700 bg-white shadow-inner object-contain"
        >
          <rect x="0" y="0" width={@screen_w} height={@screen_h} fill="white" />
          <%= for op <- @svg_ops do %>
            <rect
              :if={op.kind == :clear}
              x="0"
              y="0"
              width={@screen_w}
              height={@screen_h}
              fill={debugger_svg_color(op.color, "white")}
            />
            <image
              :if={op.kind == :bitmap_in_rect and is_binary(op[:href])}
              x={op.x}
              y={op.y}
              width={op.w}
              height={op.h}
              href={op.href}
              preserveAspectRatio="none"
            />
            <image
              :if={op.kind == :rotated_bitmap and is_binary(op[:href])}
              x={op.center_x - div(op.src_w, 2)}
              y={op.center_y - div(op.src_h, 2)}
              width={op.src_w}
              height={op.src_h}
              href={op.href}
              transform={"rotate(#{debugger_pebble_angle_deg(op.angle)} #{op.center_x} #{op.center_y})"}
              preserveAspectRatio="none"
            />
            <rect
              :if={op.kind == :round_rect}
              x={op.x}
              y={op.y}
              width={op.w}
              height={op.h}
              rx={op.radius}
              ry={op.radius}
              fill="none"
              stroke={debugger_svg_color(op.fill, "#111111")}
              stroke-width="1"
            />
            <rect
              :if={op.kind == :rect}
              x={op.x}
              y={op.y}
              width={op.w}
              height={op.h}
              fill="none"
              stroke={debugger_svg_color(op.fill, "#111111")}
              stroke-width="1"
            />
            <rect
              :if={op.kind == :fill_rect}
              x={op.x}
              y={op.y}
              width={op.w}
              height={op.h}
              fill={debugger_svg_color(op.fill, "#111111")}
              stroke={debugger_svg_color(op.fill, "#111111")}
              stroke-width="1"
            />
            <line
              :if={op.kind == :line}
              x1={op.x1}
              y1={op.y1}
              x2={op.x2}
              y2={op.y2}
              stroke={debugger_svg_color(op.color, "#111111")}
              stroke-width="1"
            />
            <path
              :if={op.kind == :arc}
              d={debugger_arc_path(op)}
              fill="none"
              stroke="#111111"
              stroke-width="1"
            />
            <path
              :if={op.kind == :fill_radial}
              d={debugger_arc_sector_path(op)}
              fill="#111111"
              stroke="#111111"
              stroke-width="1"
            />
            <path
              :if={op.kind == :path_filled}
              d={debugger_path_d(op, true)}
              fill="#111111"
              stroke="#111111"
              stroke-width="1"
            />
            <path
              :if={op.kind == :path_outline}
              d={debugger_path_d(op, true)}
              fill="none"
              stroke="#111111"
              stroke-width="1"
            />
            <path
              :if={op.kind == :path_outline_open}
              d={debugger_path_d(op, false)}
              fill="none"
              stroke="#111111"
              stroke-width="1"
            />
            <circle
              :if={op.kind == :circle}
              cx={op.cx}
              cy={op.cy}
              r={op.r}
              fill="none"
              stroke={debugger_svg_color(op.color, "#111111")}
              stroke-width="1"
            />
            <circle
              :if={op.kind == :fill_circle}
              cx={op.cx}
              cy={op.cy}
              r={op.r}
              fill={debugger_svg_color(op.color, "#111111")}
              stroke={debugger_svg_color(op.color, "#111111")}
              stroke-width="1"
            />
            <rect
              :if={op.kind == :pixel}
              x={op.x}
              y={op.y}
              width="1"
              height="1"
              fill={debugger_svg_color(op.color, "#111111")}
            />
            <text
              :if={op.kind == :text_int}
              x={op.x}
              y={op.y}
              font-size="14"
              font-family="monospace"
              fill="#111111"
            >
              {op.text}
            </text>
            <text
              :if={op.kind == :text_label}
              x={op.x}
              y={op.y}
              font-size="11"
              font-family="sans-serif"
              fill="#111111"
            >
              {op.text}
            </text>
          <% end %>
        </svg>
        <p :if={@svg_ops == []} class="mt-1 text-center text-[10px] text-zinc-500">
          No drawable primitives found in this snapshot.
        </p>
        <p :if={@unresolved_ops != []} class="mt-1 text-center text-[10px] text-amber-700">
          {debugger_unresolved_svg_summary(@unresolved_ops)}
        </p>
      </div>
      <div
        :if={@tree}
        class="min-h-0 flex-1 overflow-auto rounded border border-zinc-200 bg-white p-2"
      >
        <.debugger_view_node node={@tree} />
      </div>
      <p :if={!@tree} class="text-[11px] text-zinc-500">No view tree in this snapshot.</p>
    </div>
    """
  end

  attr(:node, :map, required: true)

  @spec debugger_view_node(term()) :: term()
  defp debugger_view_node(assigns) do
    node = assigns.node
    type = Map.get(node, "type") || Map.get(node, :type) || "node"
    label = Map.get(node, "label") || Map.get(node, :label) || ""
    children = Map.get(node, "children") || Map.get(node, :children) || []
    box_style = debugger_preview_box_style(node)
    tone = debugger_preview_tone(type)

    assigns =
      assigns
      |> assign(:type, type)
      |> assign(:label, label)
      |> assign(:children, children)
      |> assign(:box_style, box_style)
      |> assign(:tone, tone)

    ~H"""
    <div class={["inline-block rounded border p-1 align-top shadow-sm", @tone]} style={@box_style}>
      <div class="max-w-[10rem] truncate px-0.5 text-[9px] font-mono text-zinc-700">
        {@type}<span :if={@label != ""} class="text-zinc-500"> · {@label}</span>
      </div>
      <div :if={@children != []} class="mt-1 flex flex-col gap-0.5 border-t border-zinc-200/80 pt-1">
        <.debugger_view_node :for={child <- @children} node={child} />
      </div>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:runtime, :any, required: true)

  @spec debugger_rendered_view_tree(term()) :: term()
  defp debugger_rendered_view_tree(assigns) do
    tree = debugger_rendered_tree(assigns.runtime)
    model = debugger_runtime_model(assigns.runtime)
    assigns = assign(assigns, :tree, tree) |> assign(:model, model)

    ~H"""
    <div
      id={@id}
      phx-hook="PreserveRenderedDetails"
      class="mt-1 min-h-0 flex-1 overflow-auto rounded border border-zinc-200 bg-white p-2 font-mono text-[11px] text-zinc-900"
    >
      <.debugger_rendered_node
        :if={is_map(@tree)}
        node={@tree}
        model={@model}
        depth={0}
        arg_name={nil}
        path="0"
      />
      <p :if={!is_map(@tree)} class="text-[11px] text-zinc-500">(no rendered view in snapshot)</p>
    </div>
    """
  end

  attr(:node, :map, required: true)
  attr(:model, :map, required: true)
  attr(:depth, :integer, default: 0)
  attr(:arg_name, :any, default: nil)
  attr(:path, :string, default: "0")

  @spec debugger_rendered_node(term()) :: term()
  defp debugger_rendered_node(assigns) do
    node = assigns.node
    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "node")

    children =
      (Map.get(node, "children") || Map.get(node, :children) || [])
      |> Enum.filter(&is_map/1)
      |> debugger_rendered_child_rows(node, assigns.path)
      |> Enum.reject(fn %{node: child} ->
        child_type = to_string(Map.get(child, "type") || Map.get(child, :type) || "")
        debugger_hidden_rendered_node_type?(child_type)
      end)

    assigns =
      assigns
      |> assign(:type, type)
      |> assign(
        :summary,
        DebuggerSupport.rendered_node_summary(node, assigns.model, assigns.arg_name)
      )
      |> assign(:children, children)

    ~H"""
    <div :if={!debugger_hidden_rendered_node_type?(@type)} class="pl-1">
      <div :if={@children != [] && @depth < 2} class="mt-0.5">
        <div class="text-zinc-800">{@summary}</div>
        <div class="ml-3 border-l border-zinc-200 pl-2">
          <.debugger_rendered_node
            :for={child <- @children}
            node={child.node}
            model={@model}
            depth={@depth + 1}
            arg_name={child.arg_name}
            path={child.path}
          />
        </div>
      </div>
      <details :if={@children != [] && @depth >= 2} class="mt-0.5" data-rendered-node-path={@path}>
        <summary class="cursor-pointer select-none text-zinc-800">{@summary}</summary>
        <div class="ml-3 border-l border-zinc-200 pl-2">
          <.debugger_rendered_node
            :for={child <- @children}
            node={child.node}
            model={@model}
            depth={@depth + 1}
            arg_name={child.arg_name}
            path={child.path}
          />
        </div>
      </details>
      <div :if={@children == []} class="mt-0.5 text-zinc-800">{@summary}</div>
    </div>
    """
  end

  @spec debugger_hidden_rendered_node_type?(term()) :: term()
  defp debugger_hidden_rendered_node_type?(type) when is_binary(type) do
    type in ["debuggerRenderStep", "elmcRuntimeStep"]
  end

  defp debugger_hidden_rendered_node_type?(_), do: false

  @spec debugger_rendered_child_rows([map()], map(), String.t()) :: [
          %{node: map(), arg_name: String.t() | nil, path: String.t()}
        ]
  defp debugger_rendered_child_rows(children, parent, parent_path)
       when is_list(children) and is_map(parent) and is_binary(parent_path) do
    arg_names = debugger_rendered_node_arg_names(parent, length(children))

    children
    |> Enum.with_index()
    |> Enum.map(fn {child, index} ->
      %{node: child, arg_name: Enum.at(arg_names, index), path: "#{parent_path}.#{index}"}
    end)
  end

  @spec debugger_rendered_node_arg_names(map(), non_neg_integer()) :: [String.t()]
  defp debugger_rendered_node_arg_names(parent, child_count)
       when is_map(parent) and is_integer(child_count) do
    explicit = Map.get(parent, "arg_names") || Map.get(parent, :arg_names) || []

    if explicit != [] do
      explicit
    else
      []
    end
  end

  @spec debugger_diag_field(term(), term()) :: term()
  defp debugger_diag_field(row, key) when is_map(row) and is_binary(key) do
    v =
      Map.get(row, key) ||
        case key do
          "severity" -> Map.get(row, :severity)
          "source" -> Map.get(row, :source)
          "message" -> Map.get(row, :message)
          "file" -> Map.get(row, :file)
          "line" -> Map.get(row, :line)
          "column" -> Map.get(row, :column)
          _ -> nil
        end

    case v do
      nil -> "—"
      "" -> "—"
      other -> to_string(other)
    end
  end

  @spec debugger_diag_where(term()) :: term()
  defp debugger_diag_where(row) when is_map(row) do
    file = Map.get(row, "file") || Map.get(row, :file)
    line = Map.get(row, "line") || Map.get(row, :line)
    col = Map.get(row, "column") || Map.get(row, :column)

    cond do
      file in [nil, ""] ->
        "—"

      line in [nil, ""] ->
        to_string(file)

      col in [nil, ""] ->
        "#{file}:#{line}"

      true ->
        "#{file}:#{line}:#{col}"
    end
  end

  @spec debugger_preview_box_style(term()) :: term()
  defp debugger_preview_box_style(node) when is_map(node) do
    box = Map.get(node, "box") || Map.get(node, :box)

    if is_map(box) do
      w = Map.get(box, "w") || Map.get(box, :w) || 1
      h = Map.get(box, "h") || Map.get(box, :h) || 1
      scale = 0.38
      "min-width:#{max(round(w * scale), 20)}px;min-height:#{max(round(h * scale), 12)}px"
    else
      "min-width:3rem;min-height:1.25rem"
    end
  end

  @spec debugger_preview_tone(term()) :: term()
  defp debugger_preview_tone("Window"), do: "bg-zinc-100 border-zinc-400"
  defp debugger_preview_tone("TextLayer"), do: "bg-sky-50 border-sky-300"
  defp debugger_preview_tone("Rect"), do: "bg-amber-50 border-amber-300"
  defp debugger_preview_tone("Layer"), do: "bg-violet-50 border-violet-200"
  defp debugger_preview_tone("CompanionRoot"), do: "bg-emerald-50 border-emerald-300"
  defp debugger_preview_tone("Status"), do: "bg-slate-50 border-slate-300"
  defp debugger_preview_tone("ProtocolLog"), do: "bg-teal-50 border-teal-300"
  defp debugger_preview_tone("PhoneRoot"), do: "bg-indigo-50 border-indigo-300"
  defp debugger_preview_tone("AppBar"), do: "bg-indigo-100 border-indigo-400"
  defp debugger_preview_tone("Scroll"), do: "bg-blue-50 border-blue-200"
  defp debugger_preview_tone("Card"), do: "bg-orange-50 border-orange-200"
  defp debugger_preview_tone(_), do: "bg-white border-zinc-300"

  @spec debugger_watch_svg_ops(term(), term()) :: term()
  defp debugger_watch_svg_ops(tree, runtime), do: DebuggerPreview.svg_ops(tree, runtime)

  @spec hydrate_bitmap_svg_ops(term(), term()) :: term()
  defp hydrate_bitmap_svg_ops(rows, %Project{} = project) when is_list(rows) do
    Enum.map(rows, fn
      %{kind: :bitmap_in_rect, bitmap_id: bitmap_id} = row ->
        Map.put(row, :href, bitmap_href_for(project, bitmap_id))

      %{kind: :rotated_bitmap, bitmap_id: bitmap_id} = row ->
        Map.put(row, :href, bitmap_href_for(project, bitmap_id))

      other ->
        other
    end)
  end

  defp hydrate_bitmap_svg_ops(rows, _project), do: rows

  @spec bitmap_href_for(term(), term()) :: term()
  defp bitmap_href_for(%Project{} = project, bitmap_id) when is_integer(bitmap_id) do
    with {:ok, path} <- ResourceStore.bitmap_file_path_by_id(project, bitmap_id),
         {:ok, bytes} <- File.read(path) do
      "data:#{bitmap_mime_for_path(path)};base64," <> Base.encode64(bytes)
    else
      _ -> nil
    end
  end

  defp bitmap_href_for(_project, _bitmap_id), do: nil

  @spec bitmap_mime_for_path(term()) :: term()
  defp bitmap_mime_for_path(path) when is_binary(path) do
    case path |> Path.extname() |> String.downcase() do
      ".png" -> "image/png"
      ".bmp" -> "image/bmp"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      _ -> "application/octet-stream"
    end
  end

  @spec debugger_pebble_angle_deg(term()) :: term()
  defp debugger_pebble_angle_deg(angle) when is_integer(angle) do
    angle * 360.0 / 65_536.0
  end

  defp debugger_pebble_angle_deg(_), do: 0.0

  @spec debugger_unresolved_svg_summary(term()) :: term()
  defp debugger_unresolved_svg_summary(rows), do: DebuggerPreview.unresolved_summary(rows)

  @spec debugger_rendered_tree(term()) :: term()
  defp debugger_rendered_tree(%{} = runtime) do
    model = Map.get(runtime, :model) || Map.get(runtime, "model") || %{}
    elm_introspect = Map.get(model, "elm_introspect") || Map.get(model, :elm_introspect) || %{}
    parser_tree = Map.get(elm_introspect, "view_tree") || Map.get(elm_introspect, :view_tree)

    if is_map(parser_tree) and map_size(parser_tree) > 0 do
      parser_tree
    else
      debugger_preview_tree(runtime)
    end
  end

  defp debugger_rendered_tree(runtime), do: debugger_preview_tree(runtime)

  @spec debugger_preview_tree(term()) :: term()
  defp debugger_preview_tree(%{} = runtime) do
    view_tree = Map.get(runtime, :view_tree) || Map.get(runtime, "view_tree")

    if is_map(view_tree) and map_size(view_tree) > 0 do
      view_tree
    else
      model = Map.get(runtime, :model) || Map.get(runtime, "model") || %{}
      elm_introspect = Map.get(model, "elm_introspect") || Map.get(model, :elm_introspect) || %{}
      parser_tree = Map.get(elm_introspect, "view_tree") || Map.get(elm_introspect, :view_tree)
      if is_map(parser_tree), do: parser_tree, else: nil
    end
  end

  defp debugger_preview_tree(_runtime), do: nil

  @spec debugger_preview_dimensions(term(), term()) :: term()
  defp debugger_preview_dimensions(runtime, tree) do
    model = debugger_runtime_model(runtime)
    launch = Map.get(model, "launch_context") || Map.get(model, :launch_context) || %{}
    launch_screen = Map.get(launch, "screen") || Map.get(launch, :screen) || %{}
    tree_box = if is_map(tree), do: Map.get(tree, "box") || Map.get(tree, :box) || %{}, else: %{}

    width =
      Map.get(tree_box, "w") || Map.get(tree_box, :w) ||
        Map.get(launch_screen, "width") || Map.get(launch_screen, :width) || 144

    height =
      Map.get(tree_box, "h") || Map.get(tree_box, :h) ||
        Map.get(launch_screen, "height") || Map.get(launch_screen, :height) || 168

    {debugger_dimension_int(width, 144), debugger_dimension_int(height, 168)}
  end

  @spec debugger_dimension_int(term(), term()) :: term()
  defp debugger_dimension_int(value, _fallback) when is_integer(value) and value > 0, do: value

  defp debugger_dimension_int(value, _fallback) when is_float(value) and value > 0,
    do: trunc(value)

  defp debugger_dimension_int(value, fallback) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> fallback
    end
  end

  defp debugger_dimension_int(_value, fallback), do: fallback

  @spec debugger_arc_path(term()) :: term()
  defp debugger_arc_path(op), do: DebuggerPreview.arc_path(op)

  @spec debugger_arc_sector_path(term()) :: term()
  defp debugger_arc_sector_path(op) when is_map(op) do
    arc = DebuggerPreview.arc_path(op)

    if arc == "" do
      ""
    else
      cx = (op.x || 0) + max(op.w || 1, 1) / 2.0
      cy = (op.y || 0) + max(op.h || 1, 1) / 2.0
      arc <> " L #{Float.round(cx, 2)} #{Float.round(cy, 2)} Z"
    end
  end

  defp debugger_arc_sector_path(_), do: ""

  @spec debugger_path_d(term(), term()) :: term()
  defp debugger_path_d(op, close_shape?) when is_map(op) and is_boolean(close_shape?) do
    points = Map.get(op, :points, []) || []
    offset_x = Map.get(op, :offset_x, 0) || 0
    offset_y = Map.get(op, :offset_y, 0) || 0
    rotation = Map.get(op, :rotation, 0) || 0
    rotation_rad = rotation * 2.0 * :math.pi() / 65_536.0
    cos_r = :math.cos(rotation_rad)
    sin_r = :math.sin(rotation_rad)

    transformed =
      points
      |> Enum.map(fn
        [x, y] when is_integer(x) and is_integer(y) ->
          xr = x * cos_r - y * sin_r
          yr = x * sin_r + y * cos_r
          {xr + offset_x, yr + offset_y}

        {x, y} when is_integer(x) and is_integer(y) ->
          xr = x * cos_r - y * sin_r
          yr = x * sin_r + y * cos_r
          {xr + offset_x, yr + offset_y}

        _ ->
          nil
      end)
      |> Enum.reject(&is_nil/1)

    case transformed do
      [] ->
        ""

      [{sx, sy} | rest] ->
        base =
          "M #{Float.round(sx, 2)} #{Float.round(sy, 2)} " <>
            Enum.map_join(rest, " ", fn {x, y} ->
              "L #{Float.round(x, 2)} #{Float.round(y, 2)}"
            end)

        if close_shape?, do: base <> " Z", else: base
    end
  end

  defp debugger_path_d(_op, _close_shape?), do: ""

  @spec debugger_svg_color(term(), term()) :: term()
  defp debugger_svg_color(value, _fallback) when is_integer(value) do
    case value do
      1 ->
        "#111111"

      0 ->
        "white"

      packed ->
        alpha = Bitwise.band(Bitwise.bsr(packed, 6), 0x03)
        red = Bitwise.band(Bitwise.bsr(packed, 4), 0x03)
        green = Bitwise.band(Bitwise.bsr(packed, 2), 0x03)
        blue = Bitwise.band(packed, 0x03)

        rgba_float(red, green, blue, alpha)
    end
  end

  defp debugger_svg_color(_value, fallback), do: fallback

  @spec rgba_float(term(), term(), term(), term()) :: term()
  defp rgba_float(r2, g2, b2, a2) do
    r = color_2bit_to_8bit(r2)
    g = color_2bit_to_8bit(g2)
    b = color_2bit_to_8bit(b2)
    a = Float.round(color_2bit_to_8bit(a2) / 255.0, 2)
    "rgba(#{r}, #{g}, #{b}, #{a})"
  end

  @spec color_2bit_to_8bit(term()) :: term()
  defp color_2bit_to_8bit(value) when is_integer(value), do: max(0, min(3, value)) * 85

  @spec debugger_runtime_model(term()) :: term()
  defp debugger_runtime_model(runtime), do: DebuggerPreview.runtime_model(runtime)

  @spec debugger_import_error(term()) :: term()
  defp debugger_import_error(:invalid_json), do: "Trace import failed: invalid JSON."

  defp debugger_import_error(:invalid_trace),
    do:
      "Trace import failed: not a valid export (need export_version 1, events, watch, companion, seq)."

  defp debugger_import_error(:slug_mismatch),
    do: "Trace import failed: project_slug in JSON does not match this project."

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
            cur_mod != "" and row && cur_mod in row.modules ->
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

  @spec active_tab(term()) :: term()
  defp active_tab(socket), do: active_tab(socket.assigns.tabs, socket.assigns.active_tab_id)

  defp active_tab(tabs, active_tab_id), do: Enum.find(tabs, &(&1.id == active_tab_id))

  @spec read_only_tab?(term()) :: term()
  defp read_only_tab?(%{read_only: true}), do: true
  defp read_only_tab?(_), do: false

  @spec ensure_can_modify_editor_file(term()) :: term()
  defp ensure_can_modify_editor_file(%{rel_path: rel_path} = tab) do
    cond do
      read_only_tab?(tab) ->
        {:error, :read_only_file}

      protected_editor_source_file?(rel_path) ->
        {:error, :protected_file}

      true ->
        :ok
    end
  end

  @spec protected_editor_source_file?(term()) :: term()
  defp protected_editor_source_file?(rel_path) when is_binary(rel_path),
    do: rel_path in @protected_editor_rel_paths

  defp protected_editor_source_file?(_), do: false

  @spec doc_catalog_source_root(term()) :: term()
  defp doc_catalog_source_root(socket) do
    case active_tab(socket) do
      %{source_root: sr} when is_binary(sr) ->
        sr

      _ ->
        socket.assigns.packages_target_root ||
          case socket.assigns[:project] do
            nil -> "watch"
            project -> PackagesFlow.default_packages_target_root(project)
          end
    end
  end

  @spec preferred_packages_target_root(term(), term()) :: term()
  defp preferred_packages_target_root(socket, project) do
    allowed = Packages.package_elm_json_roots(project)

    active_root =
      case active_tab(socket) do
        %{source_root: sr} when is_binary(sr) -> sr
        _ -> nil
      end

    cond do
      is_binary(active_root) and active_root in allowed ->
        active_root

      true ->
        PackagesFlow.default_packages_target_root(project)
    end
  end

  @spec schedule_compiler_check(term()) :: term()
  defp schedule_compiler_check(socket) do
    case socket.assigns[:project] do
      nil ->
        socket

      project ->
        workspace_root = Projects.project_workspace_path(project)

        socket
        |> assign(:check_status, :running)
        |> start_async(:run_check, fn ->
          Compiler.check(project.slug, workspace_root: workspace_root)
        end)
    end
  end

  @spec warm_debugger_compile_context(term(), term()) :: term()
  defp warm_debugger_compile_context(socket, project) do
    workspace_root = Projects.project_workspace_path(project)

    case Compiler.compile(project.slug, workspace_root: workspace_root) do
      {:ok, result} ->
        socket
        |> assign(:compile_status, result.status)
        |> assign(:compile_output, result.output)
        |> DebuggerBridge.sync_compile(result)

      {:error, reason} ->
        socket
        |> assign(:compile_status, :error)
        |> assign(:compile_output, inspect(reason))
        |> DebuggerBridge.sync_compile_failed(inspect(reason))
    end
  end

  @spec run_build_pipeline(term(), term(), term()) :: term()
  defp run_build_pipeline(project, workspace_root, strict?) do
    roots = build_roots(workspace_root, project.source_roots || [])

    root_results =
      roots
      |> Enum.map(fn {label, root_path} ->
        {:ok, single} = run_build_pipeline_for_root(project.slug, label, root_path, strict?)
        single
      end)

    primary =
      Enum.find(root_results, fn result -> result.label == "watch" end) ||
        List.first(root_results)

    status =
      if Enum.all?(root_results, fn result -> result.status == :ok end),
        do: :ok,
        else: :error

    output =
      root_results
      |> Enum.map(fn result ->
        [
          "=== [#{result.label}] #{result.root_path} ===",
          render_build_pipeline_output(result.check, result.compile, result.manifest)
        ]
        |> Enum.join("\n")
      end)
      |> Enum.join("\n\n")
      |> String.trim()

    {:ok,
     %{
       status: status,
       output: output,
       primary: primary,
       roots: root_results
     }}
  end

  @spec run_build_pipeline_for_root(term(), term(), term(), term()) :: term()
  defp run_build_pipeline_for_root(project_slug, label, root_path, strict?) do
    scoped_slug = "#{project_slug}:#{label}"

    with {:ok, check_result} <- Compiler.check(scoped_slug, workspace_root: root_path) do
      if check_result.status == :ok do
        with {:ok, compile_result} <-
               Compiler.compile(scoped_slug, workspace_root: root_path),
             {:ok, manifest_result} <-
               Compiler.manifest(scoped_slug, workspace_root: root_path, strict: strict?) do
          {:ok,
           %{
             label: label,
             root_path: root_path,
             status:
               if(compile_result.status == :ok and manifest_result.status == :ok,
                 do: :ok,
                 else: :error
               ),
             check: check_result,
             compile: compile_result,
             manifest: manifest_result
           }}
        end
      else
        compile_result = skipped_compile_result(root_path, "Compile skipped: check failed.")

        manifest_result =
          skipped_manifest_result(root_path, strict?, "Manifest skipped: check failed.")

        {:ok,
         %{
           label: label,
           root_path: root_path,
           status: :error,
           check: check_result,
           compile: compile_result,
           manifest: manifest_result
         }}
      end
    end
  end

  @spec run_emulator_install_flow(term(), term(), term(), term()) :: term()
  defp run_emulator_install_flow(project, workspace_root, emulator_target, package_path) do
    with {:ok, resolved_package_path} <-
           ensure_install_package_path(project, workspace_root, package_path),
         {:ok, install_result} <-
           PebbleToolchain.run_emulator(project.slug,
             emulator_target: emulator_target,
             package_path: resolved_package_path
           ) do
      {:ok, Map.put(install_result, :artifact_path, resolved_package_path)}
    end
  end

  @spec ensure_install_package_path(term(), term(), term()) :: term()
  defp ensure_install_package_path(project, workspace_root, package_path) do
    if is_binary(package_path) and package_path != "" and File.exists?(package_path) do
      {:ok, package_path}
    else
      with {:ok, packaged} <-
             PebbleToolchain.package(project.slug,
               workspace_root: workspace_root,
               target_type: project.target_type,
               project_name: project.name
             ) do
        {:ok, packaged.artifact_path}
      end
    end
  end

  @spec build_roots(term(), term()) :: term()
  defp build_roots(workspace_root, source_roots) do
    candidates =
      [{"workspace", workspace_root}] ++
        Enum.map(source_roots, fn root_name ->
          {root_name, Path.join(workspace_root, root_name)}
        end)

    roots =
      candidates
      |> Enum.uniq_by(fn {_label, path} -> path end)
      |> Enum.filter(fn {_label, path} -> File.exists?(Path.join(path, "elm.json")) end)

    if roots == [], do: [{"workspace", workspace_root}], else: roots
  end

  @spec render_build_pipeline_output(term(), term(), term()) :: term()
  defp render_build_pipeline_output(check_result, compile_result, manifest_result) do
    [
      "[check]\n",
      check_result.output || "",
      "\n\n[compile]\n",
      compile_result.output || "",
      "\n\n[manifest]\n",
      manifest_result.output || ""
    ]
    |> IO.iodata_to_binary()
    |> String.trim()
  end

  @spec skipped_compile_result(term(), term()) :: term()
  defp skipped_compile_result(workspace_root, message) do
    %{
      status: :error,
      compiled_path: workspace_root,
      revision: "—",
      cached?: false,
      output: message,
      diagnostics: []
    }
  end

  @spec skipped_manifest_result(term(), term(), term()) :: term()
  defp skipped_manifest_result(workspace_root, strict?, message) do
    %{
      status: :error,
      manifest_path: workspace_root,
      revision: "—",
      cached?: false,
      strict?: strict?,
      manifest: nil,
      output: message,
      diagnostics: []
    }
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

  @spec update_tab(term(), term()) :: term()
  defp update_tab(socket, updater) do
    tabs =
      Enum.map(socket.assigns.tabs, fn tab ->
        if tab.id == socket.assigns.active_tab_id do
          updater.(tab)
        else
          tab
        end
      end)

    assign(socket, :tabs, tabs)
  end

  @spec update_active_tab(term(), term()) :: term()
  defp update_active_tab(socket, updater) do
    if socket.assigns.active_tab_id do
      update_tab(socket, updater)
    else
      socket
    end
  end

  defp update_editor_state_tab(socket, tab_id, updater) when is_binary(tab_id) do
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

  defp update_editor_state_tab(socket, _tab_id, updater), do: update_active_tab(socket, updater)

  @spec refresh_tree(term()) :: term()
  defp refresh_tree(socket) do
    socket
    |> assign(:tree, Projects.list_source_tree(socket.assigns.project))
    |> refresh_editor_dependencies()
  end

  @spec refresh_editor_dependencies(term()) :: term()
  defp refresh_editor_dependencies(socket) do
    case socket.assigns[:project] do
      nil ->
        socket

      project ->
        root = PackagesFlow.sanitize_target_root(project, socket.assigns.packages_target_root)

        socket =
          if root != socket.assigns.packages_target_root do
            assign(socket, :packages_target_root, root)
          else
            socket
          end

        packages_root = root
        doc_root = doc_catalog_source_root(socket)
        token = System.unique_integer([:positive])

        socket
        |> assign(:editor_deps_refresh_token, token)
        |> start_async(:refresh_editor_dependencies, fn ->
          {EditorDependencies.build_payload(project, packages_root, doc_root), token}
        end)
    end
  end

  @spec editor_source_display_path(term()) :: term()
  defp editor_source_display_path("src/" <> rest), do: rest
  defp editor_source_display_path(rel) when is_binary(rel), do: rel

  @spec editor_file_tree_label(term(), term()) :: term()
  defp editor_file_tree_label("protocol", rel_path) when is_binary(rel_path) do
    rel_path
    |> editor_source_display_path()
    |> case do
      "Companion/" <> rest -> rest
      other -> other
    end
  end

  defp editor_file_tree_label(_source_root, rel_path) when is_binary(rel_path) do
    editor_source_display_path(rel_path)
  end

  @spec normalize_editor_src_rel_path(term()) :: term()
  defp normalize_editor_src_rel_path(path) when is_binary(path) do
    path = path |> String.trim() |> String.trim_leading("/")

    cond do
      path == "" ->
        ""

      String.starts_with?(path, "src/") ->
        path

      true ->
        "src/" <> path
    end
  end

  @spec settings_path_with_return_to(term()) :: term()
  defp settings_path_with_return_to(return_to) when is_binary(return_to) do
    "/settings?return_to=#{URI.encode_www_form(return_to)}"
  end

  @spec module_name_from_rel_path(term()) :: term()
  defp module_name_from_rel_path("src/" <> rel_path) when is_binary(rel_path) do
    module_name =
      rel_path
      |> String.trim()
      |> Path.rootname()
      |> String.split("/", trim: true)
      |> Enum.join(".")

    cond do
      module_name == "" ->
        {:error, :invalid_rel_path}

      not String.ends_with?(rel_path, ".elm") ->
        {:error, :invalid_extension}

      true ->
        {:ok, module_name}
    end
  end

  defp module_name_from_rel_path(_), do: {:error, :invalid_rel_path}

  @spec validate_new_elm_module_name(term()) :: term()
  defp validate_new_elm_module_name(module_name) when is_binary(module_name) do
    module_name
    |> String.split(".", trim: true)
    |> case do
      [] ->
        {:error, :invalid_module_name}

      segments ->
        if Enum.all?(segments, &elm_module_segment?/1) do
          :ok
        else
          {:error, :invalid_module_name}
        end
    end
  end

  @spec elm_module_segment?(term()) :: term()
  defp elm_module_segment?(segment) when is_binary(segment) do
    String.match?(segment, ~r/^[A-Z][A-Za-z0-9_]*$/)
  end

  defp elm_module_segment?(_), do: false

  @spec new_elm_module_template(term()) :: term()
  defp new_elm_module_template(module_name) when is_binary(module_name) do
    "module #{module_name} exposing (..)\n\n"
  end

  @spec maybe_initialize_forms(term(), term()) :: term()
  defp maybe_initialize_forms(socket, project) do
    source_root = List.first(project.source_roots) || "watch"

    socket
    |> assign(
      :new_file_form,
      to_form(%{"source_root" => source_root, "rel_path" => ""}, as: :new_file)
    )
    |> assign(:rename_form, to_form(%{"new_rel_path" => ""}, as: :rename))
  end

  defp maybe_open_editor_default_file(socket, project, previous_pane) do
    if socket.assigns.live_action == :editor and
         (previous_pane != :editor or is_nil(active_tab(socket))) do
      open_editor_default_file(socket, project)
    else
      socket
    end
  end

  defp open_editor_default_file(socket, project) do
    Enum.reduce_while(editor_entry_candidates(), socket, fn {source_root, rel_path}, acc ->
      tab_id = tab_id(source_root, rel_path)

      case active_tab(acc.assigns.tabs, tab_id) do
        nil ->
          case Projects.read_source_file(project, source_root, rel_path) do
            {:ok, contents} ->
              editor_state = default_editor_state()

              tab = %{
                id: tab_id,
                source_root: source_root,
                rel_path: rel_path,
                content: contents,
                dirty: false,
                read_only: ResourceStore.read_only_generated_module?(source_root, rel_path),
                editor_state: editor_state
              }

              next =
                acc
                |> assign(:opening_file_id, nil)
                |> assign(:opening_file_label, nil)
                |> assign(:file_open_token, nil)
                |> assign(tabs: acc.assigns.tabs ++ [tab], active_tab_id: tab.id)
                |> assign(:active_diagnostic_index, editor_state.active_diagnostic_index)
                |> assign_tokenization(contents, rel_path, mode: :compiler)
                |> restore_editor_state(editor_state)

              {:halt, next}

            {:error, _reason} ->
              {:cont, acc}
          end

        existing_tab ->
          selected_state = existing_tab.editor_state || %{}

          next =
            acc
            |> assign(:active_tab_id, tab_id)
            |> assign(:opening_file_id, nil)
            |> assign(:opening_file_label, nil)
            |> assign(:file_open_token, nil)
            |> assign(:active_diagnostic_index, selected_state[:active_diagnostic_index])
            |> assign_tokenization(existing_tab.content, existing_tab.rel_path)
            |> restore_editor_state(selected_state)

          {:halt, next}
      end
    end)
  end

  defp editor_entry_candidates do
    [{"watch", "src/Main.elm"}, {"watch", "Main.elm"}]
  end

  defp default_editor_state do
    %{
      cursor_offset: 0,
      scroll_top: 0,
      scroll_left: 0,
      active_diagnostic_index: 0
    }
  end

  @spec tab_id(term(), term()) :: term()
  defp tab_id(source_root, rel_path), do: "#{source_root}:#{rel_path}"

  @spec tree_dir_key(term(), term()) :: term()
  defp tree_dir_key(source_root, rel_path), do: "#{source_root}:#{rel_path}"

  @spec maybe_put_kw(term(), term(), term()) :: term()
  defp maybe_put_kw(opts, _key, nil), do: opts
  defp maybe_put_kw(opts, _key, ""), do: opts
  defp maybe_put_kw(opts, key, value), do: Keyword.put(opts, key, value)

  @spec apply_text_patch(term(), term()) :: term()
  defp apply_text_patch(content, %{replace_from: from, replace_to: to, inserted_text: inserted})
       when is_binary(content) and is_integer(from) and is_integer(to) and is_binary(inserted) do
    String.slice(content, 0, from) <>
      inserted <> String.slice(content, to, String.length(content) - to)
  end

  @spec identity_edit_patch(term(), term(), term()) :: term()
  defp identity_edit_patch(content, start_offset, end_offset) when is_binary(content) do
    %{
      replace_from: start_offset,
      replace_to: end_offset,
      inserted_text: String.slice(content, start_offset, end_offset - start_offset),
      cursor_start: start_offset,
      cursor_end: end_offset
    }
  end

  @spec semantic_edit_ops_enabled?() :: term()
  defp semantic_edit_ops_enabled? do
    Application.get_env(:ide, Ide.Formatter, [])
    |> Keyword.get(:semantic_edit_ops, true)
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

  @spec render_capture_all_progress(term()) :: term()
  defp render_capture_all_progress({:phase, message}) when is_binary(message), do: message

  defp render_capture_all_progress({:target, target, :cleanup_before}),
    do: "[#{target}] Cleaning previous emulator..."

  defp render_capture_all_progress({:target, target, :installing}),
    do: "[#{target}] Installing app..."

  defp render_capture_all_progress({:target, target, :capturing}),
    do: "[#{target}] Capturing screenshot..."

  defp render_capture_all_progress({:target, target, :capture_attempt, attempt, total}),
    do: "[#{target}] Capture attempt #{attempt}/#{total}..."

  defp render_capture_all_progress({:target, target, :capture_retry, attempt, total, reason}),
    do: "[#{target}] Attempt #{attempt}/#{total} failed: #{inspect(reason)}"

  defp render_capture_all_progress({:target, target, :ok}), do: "[#{target}] Screenshot captured."

  defp render_capture_all_progress({:target, target, :captured, _screenshot}),
    do: "[#{target}] Screenshot added to gallery."

  defp render_capture_all_progress({:target, target, :cleanup_after}),
    do: "[#{target}] Closing emulator..."

  defp render_capture_all_progress({:target, target, :cleanup_error, _phase, reason}),
    do: "[#{target}] Cleanup warning: #{inspect(reason)}"

  defp render_capture_all_progress({:target, target, :error, reason}),
    do: "[#{target}] Failed: #{inspect(reason)}"

  defp render_capture_all_progress({:close, {:ok, _result}}), do: "Emulators stopped."

  defp render_capture_all_progress({:close, {:error, reason}}),
    do: "Could not stop emulators: #{inspect(reason)}"

  defp render_capture_all_progress(_), do: "Working..."

  @spec update_capture_target_statuses(term(), term()) :: term()
  defp update_capture_target_statuses(statuses, {:target, target, :cleanup_before}),
    do: Map.put(statuses, target, "cleaning previous emulator")

  defp update_capture_target_statuses(statuses, {:target, target, :installing}),
    do: Map.put(statuses, target, "installing")

  defp update_capture_target_statuses(statuses, {:target, target, :capturing}),
    do: Map.put(statuses, target, "capturing")

  defp update_capture_target_statuses(
         statuses,
         {:target, target, :capture_attempt, attempt, total}
       ),
       do: Map.put(statuses, target, "capture attempt #{attempt}/#{total}")

  defp update_capture_target_statuses(
         statuses,
         {:target, target, :capture_retry, attempt, total, _reason}
       ),
       do: Map.put(statuses, target, "retrying after attempt #{attempt}/#{total}")

  defp update_capture_target_statuses(statuses, {:target, target, :ok}),
    do: Map.put(statuses, target, "done")

  defp update_capture_target_statuses(statuses, {:target, target, :cleanup_after}),
    do: keep_capture_terminal_status(statuses, target, "closing emulator")

  defp update_capture_target_statuses(
         statuses,
         {:target, target, :cleanup_error, _phase, reason}
       ),
       do: keep_capture_terminal_status(statuses, target, "cleanup warning: #{inspect(reason)}")

  defp update_capture_target_statuses(statuses, {:target, target, :error, reason}),
    do: Map.put(statuses, target, "error: #{inspect(reason)}")

  defp update_capture_target_statuses(statuses, {:phase, message}) when is_binary(message) do
    case Regex.run(~r/^\[(\d+)\/(\d+)\]\s+([a-z0-9_-]+)/i, message) do
      [_, _idx, _total, target] -> Map.put(statuses, target, "running")
      _ -> statuses
    end
  end

  defp update_capture_target_statuses(statuses, _msg), do: statuses

  @spec maybe_merge_capture_progress_screenshot(term(), term()) :: term()
  defp maybe_merge_capture_progress_screenshot(socket, {:target, _target, :captured, screenshot})
       when is_map(screenshot) do
    shots = upsert_screenshot(socket.assigns.screenshots || [], screenshot)

    socket
    |> assign(:screenshots, shots)
    |> assign(:screenshot_groups, group_screenshots(shots))
  end

  defp maybe_merge_capture_progress_screenshot(socket, _msg), do: socket

  @spec upsert_screenshot(term(), term()) :: term()
  defp upsert_screenshot(existing, screenshot) do
    key = screenshot_identity(screenshot)

    existing
    |> Enum.reject(fn item -> screenshot_identity(item) == key end)
    |> Kernel.++([screenshot])
    |> Enum.sort_by(&screenshot_sort_key/1, :desc)
  end

  @spec screenshot_identity(term()) :: term()
  defp screenshot_identity(item) when is_map(item) do
    cond do
      is_binary(item[:absolute_path]) and item[:absolute_path] != "" ->
        {:path, item[:absolute_path]}

      is_binary(item[:filename]) and item[:filename] != "" ->
        {:filename, item[:filename]}

      true ->
        {:fallback, inspect(item)}
    end
  end

  @spec screenshot_sort_key(term()) :: term()
  defp screenshot_sort_key(item) when is_map(item) do
    case item[:captured_at] do
      %DateTime{} = dt -> DateTime.to_unix(dt, :microsecond)
      %NaiveDateTime{} = dt -> NaiveDateTime.to_iso8601(dt)
      other when is_binary(other) -> other
      _ -> ""
    end
  end

  @spec keep_capture_terminal_status(term(), term(), term()) :: term()
  defp keep_capture_terminal_status(statuses, target, next_status) do
    case Map.get(statuses, target) do
      "done" -> statuses
      "error: " <> _ = error_status -> Map.put(statuses, target, error_status)
      _ -> Map.put(statuses, target, next_status)
    end
  end

  @spec merge_capture_all_result_statuses(term(), term()) :: term()
  defp merge_capture_all_result_statuses(statuses, result) when is_map(result) do
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

  defp merge_capture_all_result_statuses(statuses, _result), do: statuses

  @spec emulator_install_error_message(term()) :: term()
  defp emulator_install_error_message(:package_path_required) do
    "No installable artifact selected. Generate a `.pbw` artifact first, then install it to the emulator."
  end

  defp emulator_install_error_message({:package_path_not_found, path}) do
    "Selected artifact was not found: #{path}"
  end

  defp emulator_install_error_message({:package_path_not_pbw, path}) do
    "Selected artifact is not a `.pbw` file: #{path}"
  end

  defp emulator_install_error_message(reason) do
    "Emulator install failed before execution: #{inspect(reason)}"
  end

  @spec render_format_output(term()) :: term()
  defp render_format_output(result) do
    diagnostics =
      case result.diagnostics do
        [] -> "none"
        items -> Enum.map_join(items, "\n", &format_diagnostic_line/1)
      end

    """
    formatter: #{result.formatter}
    changed: #{result.changed?}
    parser_payload_reused: #{format_parser_reuse(result)}
    diagnostics: #{diagnostics}
    """
  end

  @spec format_parser_reuse(term()) :: term()
  defp format_parser_reuse(%{details: %{parser_payload_reused?: value}}), do: value
  defp format_parser_reuse(_), do: "unknown"

  @spec formatted_cursor_offset(term(), String.t()) :: non_neg_integer()
  defp formatted_cursor_offset(socket, formatted_source) do
    cursor =
      socket
      |> active_tab()
      |> case do
        %{editor_state: state} -> editor_cursor_offset(state)
        _ -> 0
      end

    min(cursor, String.length(formatted_source))
  end

  @spec editor_cursor_offset(term()) :: non_neg_integer()
  defp editor_cursor_offset(state) when is_map(state) do
    case Map.get(state, :cursor_offset, Map.get(state, "cursor_offset", 0)) do
      value when is_integer(value) and value >= 0 -> value
      _ -> 0
    end
  end

  defp editor_cursor_offset(_), do: 0

  @spec render_format_error(term()) :: term()
  defp render_format_error(reason) when is_map(reason) do
    format_diagnostic_line(reason)
  end

  defp render_format_error(reason), do: inspect(reason)

  @spec format_diagnostic_line(term()) :: term()
  defp format_diagnostic_line(diag) do
    source = diag[:source] || "formatter"
    line = diag[:line] || "?"
    column = diag[:column] || "?"
    message = diag[:message] || inspect(diag)

    structured =
      diag
      |> diagnostic_structured_lines()
      |> case do
        [] -> ""
        lines -> " (" <> Enum.join(lines, ", ") <> ")"
      end

    "[#{source}] #{line}:#{column} #{message}#{structured}"
  end

  @spec diagnostic_structured_lines(term()) :: term()
  defp diagnostic_structured_lines(diag) when is_map(diag) do
    []
    |> maybe_diag_detail(
      "code",
      diag[:warning_code] || diag["warning_code"] || diag[:code] || diag["code"]
    )
    |> maybe_diag_detail(
      "constructor",
      diag[:warning_constructor] || diag["warning_constructor"] || diag[:constructor] ||
        diag["constructor"]
    )
    |> maybe_diag_detail(
      "expected",
      diag[:warning_expected_kind] || diag["warning_expected_kind"] || diag[:expected_kind] ||
        diag["expected_kind"]
    )
    |> maybe_diag_detail(
      "has_arg_pattern",
      diag[:warning_has_arg_pattern] || diag["warning_has_arg_pattern"] || diag[:has_arg_pattern] ||
        diag["has_arg_pattern"]
    )
  end

  defp diagnostic_structured_lines(_), do: []

  @spec maybe_diag_detail(term(), term(), term()) :: term()
  defp maybe_diag_detail(lines, _label, nil), do: lines

  defp maybe_diag_detail(lines, label, value) do
    rendered =
      case value do
        atom when is_atom(atom) -> Atom.to_string(atom)
        other -> to_string(other)
      end

    lines ++ ["#{label}=#{rendered}"]
  end

  @spec bitmap_upload_output(term()) :: term()
  defp bitmap_upload_output([]), do: "No file uploaded."

  defp bitmap_upload_output(results) when is_list(results) do
    ok_count = Enum.count(results, &is_map/1)
    "Uploaded #{ok_count} bitmap#{if ok_count == 1, do: "", else: "s"}."
  end

  @spec font_upload_output(term()) :: term()
  defp font_upload_output([]), do: "No file uploaded."

  defp font_upload_output(results) when is_list(results) do
    ok_count = Enum.count(results, &is_map/1)
    "Uploaded #{ok_count} font#{if ok_count == 1, do: "", else: "s"}."
  end

  @spec load_bitmap_resources(term()) :: term()
  defp load_bitmap_resources(%Project{} = project) do
    case Projects.list_bitmap_resources(project) do
      {:ok, entries} ->
        Enum.with_index(entries, 1)
        |> Enum.map(fn {entry, idx} ->
          preview_data_url =
            case ResourceStore.bitmap_file_path(project, entry.ctor) do
              {:ok, path} -> bitmap_preview_data_url(path, entry.mime)
              _ -> nil
            end

          entry
          |> Map.put(:resource_id, idx)
          |> Map.put(:preview_data_url, preview_data_url)
        end)

      _ ->
        []
    end
  end

  @spec load_font_resources(term()) :: term()
  defp load_font_resources(%Project{} = project) do
    case Projects.list_font_resources(project) do
      {:ok, entries} ->
        Enum.with_index(entries, 1)
        |> Enum.map(fn {entry, idx} ->
          entry
          |> Map.put(:resource_id, idx)
        end)

      _ ->
        []
    end
  end

  @spec bitmap_preview_data_url(term(), term()) :: term()
  defp bitmap_preview_data_url(path, mime) when is_binary(path) and is_binary(mime) do
    with {:ok, bytes} <- File.read(path) do
      "data:#{mime};base64," <> Base.encode64(bytes)
    else
      _ -> nil
    end
  end

  @spec load_screenshots(term()) :: term()
  defp load_screenshots(project) do
    case Screenshots.list(project.slug, []) do
      {:ok, shots} -> shots
      _ -> []
    end
  end

  @spec group_screenshots(term()) :: term()
  defp group_screenshots(shots) do
    shots
    |> Enum.group_by(& &1.emulator_target)
    |> Enum.sort_by(fn {emulator_target, _} -> emulator_target end)
  end

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

  @spec project_settings_form_data(term()) :: map()
  defp project_settings_form_data(%Project{} = project) do
    defaults = project.release_defaults || %{}
    github = Projects.github_config(project)

    %{
      "version_label" => Map.get(defaults, "version_label", ""),
      "tags" => Map.get(defaults, "tags", ""),
      "github_owner" => Map.get(github, "owner", ""),
      "github_repo" => Map.get(github, "repo", ""),
      "github_branch" => Map.get(github, "branch", "main")
    }
  end

  defp project_settings_form_data(_),
    do: %{
      "version_label" => "",
      "tags" => "",
      "github_owner" => "",
      "github_repo" => "",
      "github_branch" => "main"
    }

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

  @spec project_debugger_timeline_mode(Project.t()) :: String.t()
  defp project_debugger_timeline_mode(%Project{} = project) do
    settings = project.debugger_settings || %{}

    case Map.get(settings, "timeline_mode") do
      mode when mode in ["watch", "companion", "mixed", "separate"] -> mode
      _ -> "mixed"
    end
  end

  @spec project_debugger_watch_profile_id(Project.t()) :: String.t()
  defp project_debugger_watch_profile_id(%Project{} = project) do
    settings = project.debugger_settings || %{}
    normalize_debugger_watch_profile_id(Map.get(settings, "watch_profile_id"))
  end

  @spec selected_debugger_watch_profile_id(term(), term()) :: String.t()
  defp selected_debugger_watch_profile_id(%{watch_profile_id: watch_profile_id}, _project)
       when is_binary(watch_profile_id) do
    normalize_debugger_watch_profile_id(watch_profile_id)
  end

  defp selected_debugger_watch_profile_id(_debugger_state, project),
    do: project_debugger_watch_profile_id(project)

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

        contains_any?(normalized_trigger, ["on_tick", "ontick", "tick"]) ->
          {"none", "", constructor}

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
        @debugger_auto_fire_refresh_interval_ms
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

  @spec debugger_auto_fire_enabled?(Project.t(), term()) :: boolean()
  defp debugger_auto_fire_enabled?(%Project{} = project, target) do
    settings = project.debugger_settings || %{}
    auto_fire = Map.get(settings, "auto_fire", %{})
    Map.get(auto_fire, debugger_auto_fire_target(target)) == true
  end

  @spec debugger_auto_fire_target(term()) :: String.t()
  defp debugger_auto_fire_target("protocol"), do: "protocol"
  defp debugger_auto_fire_target("companion"), do: "protocol"
  defp debugger_auto_fire_target(:protocol), do: "protocol"
  defp debugger_auto_fire_target(:companion), do: "protocol"
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

  @spec tokenize_content(term(), term(), term()) :: term()
  defp tokenize_content(content, rel_path, opts) do
    if elm_source_file?(rel_path) do
      result = Tokenizer.tokenize(content, opts)

      classes =
        result.tokens
        |> Enum.group_by(& &1.class)
        |> Enum.map(fn {klass, items} -> {klass, length(items)} end)
        |> Enum.sort_by(fn {klass, _} -> klass end)

      %{
        tokens: result.tokens,
        summary: %{total: length(result.tokens), classes: classes},
        diagnostics: result.diagnostics,
        formatter_parser_payload: result[:formatter_parser_payload]
      }
    else
      %{
        tokens: [
          %{text: content, class: "plain", line: 1, column: 1, length: String.length(content)}
        ],
        summary: nil,
        diagnostics: [],
        formatter_parser_payload: nil
      }
    end
  end

  @spec assign_tokenization(term(), term(), term(), term()) :: term()
  defp assign_tokenization(socket, content, rel_path, opts \\ [])

  defp assign_tokenization(socket, nil, _rel_path, _opts) do
    socket
    |> assign(:token_tokens, [])
    |> assign(:token_summary, nil)
    |> assign(:token_diagnostics, [])
    |> assign(:formatter_parser_payload, nil)
    |> assign(:tokenizer_mode, :fast)
    |> assign(:editor_line_count, 1)
    |> assign(:token_diag_by_line, %{})
    |> assign(:editor_inline_diagnostics, [])
    |> assign(:active_diagnostic_index, nil)
  end

  defp assign_tokenization(socket, content, rel_path, opts) do
    tokenized = tokenize_content(content, rel_path, opts)

    tokenizer_mode =
      if(elm_source_file?(rel_path), do: Keyword.get(opts, :mode, :fast), else: :plain)

    annotated_tokens = annotate_tokens_with_diagnostics(tokenized.tokens, tokenized.diagnostics)
    lines = String.split(content, "\n", trim: false)
    editor_line_count = max(length(lines), 1)
    token_diag_by_line = token_diagnostics_by_line(tokenized.diagnostics)
    inline_diagnostics = inline_diagnostics(tokenized.diagnostics, lines)

    socket
    |> assign(:token_tokens, annotated_tokens)
    |> assign(:token_summary, tokenized.summary)
    |> assign(:token_diagnostics, tokenized.diagnostics)
    |> assign(:formatter_parser_payload, tokenized.formatter_parser_payload)
    |> assign(:tokenizer_mode, tokenizer_mode)
    |> assign(:editor_line_count, editor_line_count)
    |> assign(:token_diag_by_line, token_diag_by_line)
    |> assign(:editor_inline_diagnostics, inline_diagnostics)
    |> assign(
      :active_diagnostic_index,
      normalize_active_diagnostic_index(
        socket.assigns[:active_diagnostic_index],
        inline_diagnostics
      )
    )
    |> push_editor_token_highlights(annotated_tokens, tokenizer_mode)
    |> push_editor_fold_ranges(content, annotated_tokens, tokenized.formatter_parser_payload)
    |> push_editor_lint_diagnostics(tokenized.diagnostics)
    |> sync_parser_panel_from_tokenizer(rel_path, tokenizer_mode)
    |> sync_active_diagnostic_index_to_tab()
  end

  @spec sync_parser_panel_from_tokenizer(term(), term(), term()) :: term()
  defp sync_parser_panel_from_tokenizer(socket, rel_path, :compiler) when is_binary(rel_path) do
    diagnostics =
      socket.assigns.token_diagnostics
      |> Enum.map(fn diag ->
        diag
        |> Map.put(:file, rel_path)
        |> Map.put_new(:source, "tokenizer")
      end)

    assign(socket, :diagnostics, diagnostics)
  end

  defp sync_parser_panel_from_tokenizer(socket, _rel_path, _mode), do: socket

  @spec push_editor_token_highlights(term(), term(), term()) :: term()
  defp push_editor_token_highlights(socket, tokens, tokenizer_mode) do
    if connected?(socket) do
      payload_tokens =
        tokens
        |> Enum.reject(&(&1.class in ["whitespace", "plain"]))
        |> Enum.take(@max_editor_highlight_tokens)
        |> Enum.map(fn token ->
          %{
            line: token.line,
            column: token.column,
            length: token.length,
            class: token.class
          }
        end)

      push_event(socket, "token-editor-token-highlights", %{
        mode: Atom.to_string(tokenizer_mode),
        tokens: payload_tokens
      })
    else
      socket
    end
  end

  @spec push_editor_fold_ranges(term(), term(), term(), term()) :: term()
  defp push_editor_fold_ranges(socket, content, tokens, parser_payload)
       when is_binary(content) and is_list(tokens) do
    if connected?(socket) do
      line_count = max(length(String.split(content, "\n", trim: false)), 1)

      ranges =
        parser_header_fold_ranges(parser_payload)
        |> Kernel.++(type_declaration_fold_ranges(content))
        |> Kernel.++(top_level_declaration_fold_ranges(content))
        |> Kernel.++(token_delimiter_fold_ranges(tokens))
        |> Kernel.++(token_comment_fold_ranges(tokens))
        |> Enum.map(fn %{start_line: start_line, end_line: end_line} ->
          %{
            start_line: start_line,
            end_line: min(max(end_line, start_line + 1), line_count)
          }
        end)
        |> Enum.filter(fn %{start_line: start_line, end_line: end_line} ->
          start_line >= 1 and end_line > start_line
        end)
        |> Enum.uniq_by(fn %{start_line: start_line, end_line: end_line} ->
          {start_line, end_line}
        end)
        |> Enum.sort_by(fn %{start_line: start_line, end_line: end_line} ->
          {start_line, end_line}
        end)
        |> Enum.take(@max_editor_fold_ranges)

      push_event(socket, "token-editor-fold-ranges", %{ranges: ranges})
    else
      socket
    end
  end

  defp push_editor_fold_ranges(socket, _content, _tokens, _parser_payload), do: socket

  @spec push_editor_lint_diagnostics(term(), term()) :: term()
  defp push_editor_lint_diagnostics(socket, diagnostics) when is_list(diagnostics) do
    if connected?(socket) do
      payload =
        diagnostics
        |> Enum.take(@max_editor_lint_diagnostics)
        |> Enum.map(fn diag ->
          %{
            line: diagnostic_value(diag, :line),
            column: diagnostic_value(diag, :column),
            end_line: diagnostic_value(diag, :end_line),
            end_column: diagnostic_value(diag, :end_column),
            severity: diagnostic_value(diag, :severity),
            source: diagnostic_value(diag, :source),
            message: diagnostic_value(diag, :message)
          }
        end)

      push_event(socket, "token-editor-lint-diagnostics", %{diagnostics: payload})
    else
      socket
    end
  end

  @spec diagnostic_value(term(), term()) :: term()
  defp diagnostic_value(diag, key) when is_map(diag) and is_atom(key) do
    Map.get(diag, key) || Map.get(diag, Atom.to_string(key))
  end

  defp diagnostic_value(_diag, _key), do: nil

  @spec parser_header_fold_ranges(term()) :: term()
  defp parser_header_fold_ranges(%{metadata: metadata}) when is_map(metadata) do
    header_lines = metadata[:header_lines] || %{}
    module_line = header_lines[:module]
    import_lines = header_lines[:imports] || []
    sorted_import_lines = import_lines |> List.wrap() |> Enum.filter(&is_integer/1) |> Enum.sort()

    module_fold =
      case {module_line, sorted_import_lines} do
        {line, [first_import | _]} when is_integer(line) and first_import > line ->
          [%{start_line: line, end_line: first_import - 1}]

        _ ->
          []
      end

    imports_fold =
      case sorted_import_lines do
        [first | _] = lines ->
          last = List.last(lines)
          if last > first, do: [%{start_line: first, end_line: last}], else: []

        _ ->
          []
      end

    module_fold ++ imports_fold
  end

  defp parser_header_fold_ranges(_), do: []

  @spec top_level_declaration_fold_ranges(term()) :: term()
  defp top_level_declaration_fold_ranges(content) when is_binary(content) do
    lines = String.split(content, "\n", trim: false)
    line_count = length(lines)

    starts =
      lines
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _line_no} -> top_level_fold_start_line?(line) end)
      |> Enum.map(&elem(&1, 1))

    starts
    |> Enum.with_index()
    |> Enum.flat_map(fn {start_line, idx} ->
      next_start = Enum.at(starts, idx + 1, line_count + 1)
      end_line = last_non_blank_line(lines, next_start - 1)

      if is_integer(end_line) and end_line > start_line do
        [%{start_line: start_line, end_line: end_line}]
      else
        []
      end
    end)
  end

  @spec type_declaration_fold_ranges(term()) :: term()
  defp type_declaration_fold_ranges(content) when is_binary(content) do
    lines = String.split(content, "\n", trim: false)
    line_count = length(lines)

    starts =
      lines
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _line_no} -> type_declaration_start_line?(line) end)
      |> Enum.map(&elem(&1, 1))

    all_decl_starts =
      lines
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _line_no} -> top_level_fold_start_line?(line) end)
      |> Enum.map(&elem(&1, 1))
      |> Enum.sort()

    starts
    |> Enum.flat_map(fn start_line ->
      next_start =
        all_decl_starts
        |> Enum.find(fn line_no -> line_no > start_line end)
        |> case do
          nil -> line_count + 1
          line_no -> line_no
        end

      end_line = last_non_blank_line(lines, next_start - 1)

      if is_integer(end_line) and end_line > start_line do
        [%{start_line: start_line, end_line: end_line}]
      else
        []
      end
    end)
  end

  @spec type_declaration_start_line?(term()) :: term()
  defp type_declaration_start_line?(line) when is_binary(line) do
    trimmed = String.trim_leading(line)
    indent = String.length(line) - String.length(trimmed)

    indent == 0 and
      (Regex.match?(~r/^type\s+alias\s+[A-Z][A-Za-z0-9_']*/, trimmed) or
         Regex.match?(~r/^type\s+[A-Z][A-Za-z0-9_']*/, trimmed))
  end

  @spec top_level_fold_start_line?(term()) :: term()
  defp top_level_fold_start_line?(line) when is_binary(line) do
    trimmed = String.trim_leading(line)
    indent = String.length(line) - String.length(trimmed)

    indent == 0 and trimmed != "" and
      (Regex.match?(~r/^(module|import|type|type alias|port|infix|infixl|infixr)\b/, trimmed) or
         Regex.match?(~r/^[a-z_][A-Za-z0-9_']*\s*:/, trimmed) or
         Regex.match?(~r/^[a-z_][A-Za-z0-9_']*(\s+[^=].*)?\s*=\s*/, trimmed) or
         Regex.match?(~r/^\([^)]+\)\s*:/, trimmed) or
         Regex.match?(~r/^\([^)]+\)\s+.*=\s*/, trimmed))
  end

  @spec last_non_blank_line(term(), term()) :: term()
  defp last_non_blank_line(lines, from_line) when is_list(lines) and is_integer(from_line) do
    max_line = min(from_line, length(lines))

    if max_line < 1 do
      nil
    else
      max_line..1
      |> Enum.find(fn line_no ->
        line = Enum.at(lines, line_no - 1, "")
        String.trim(line) != ""
      end)
    end
  end

  @spec token_comment_fold_ranges(term()) :: term()
  defp token_comment_fold_ranges(tokens) do
    Enum.flat_map(tokens, fn token ->
      text = token[:text] || token[:token] || token[:value]
      klass = token[:class]
      line = token[:line]

      if klass == "comment" and is_binary(text) and is_integer(line) and
           String.starts_with?(text, "{-") do
        line_breaks = length(:binary.matches(text, "\n"))
        end_line = line + line_breaks
        if end_line > line, do: [%{start_line: line, end_line: end_line}], else: []
      else
        []
      end
    end)
  end

  @spec token_delimiter_fold_ranges(term()) :: term()
  defp token_delimiter_fold_ranges(tokens) do
    {stack, ranges} =
      Enum.reduce(tokens, {[], []}, fn token, {stack, ranges} ->
        text = token[:text]
        klass = token[:class]
        line = token[:line]

        if is_integer(line) and klass in ["delimiter", "operator"] and is_binary(text) do
          cond do
            text in ["(", "[", "{"] ->
              {[{text, line} | stack], ranges}

            text in [")", "]", "}"] ->
              case stack do
                [{open_text, open_line} | rest] ->
                  if delimiter_match?(open_text, text) and
                       line - open_line >= @min_bracket_fold_span_lines do
                    {rest, [%{start_line: open_line, end_line: line} | ranges]}
                  else
                    {stack, ranges}
                  end

                _ ->
                  {stack, ranges}
              end

            true ->
              {stack, ranges}
          end
        else
          {stack, ranges}
        end
      end)

    _ = stack
    ranges
  end

  @spec delimiter_match?(term(), term()) :: term()
  defp delimiter_match?("(", ")"), do: true
  defp delimiter_match?("[", "]"), do: true
  defp delimiter_match?("{", "}"), do: true
  defp delimiter_match?(_, _), do: false

  @spec elm_source_file?(term()) :: term()
  defp elm_source_file?(rel_path) when is_binary(rel_path),
    do: String.ends_with?(rel_path, ".elm")

  defp elm_source_file?(_), do: false

  @spec annotate_tokens_with_diagnostics(term(), term()) :: term()
  defp annotate_tokens_with_diagnostics(tokens, diagnostics) do
    Enum.map(tokens, fn token ->
      messages =
        diagnostics
        |> Enum.filter(&diagnostic_hits_token?(&1, token))
        |> Enum.map(&format_diagnostic_message/1)
        |> Enum.uniq()

      Map.put(token, :diagnostic_messages, messages)
    end)
  end

  @spec format_diagnostic_message(term()) :: term()
  defp format_diagnostic_message(diag) do
    line = diag[:line] || "?"
    column = diag[:column] || "?"
    "[#{diag.severity}] #{diag.source} @ #{line}:#{column} - #{diag.message}"
  end

  @spec parse_positive_int(term()) :: term()
  defp parse_positive_int(nil), do: nil

  defp parse_positive_int(value) when is_integer(value) and value > 0, do: value

  defp parse_positive_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> nil
    end
  end

  defp parse_positive_int(_), do: nil

  @spec parse_non_negative_int(term()) :: term()
  defp parse_non_negative_int(nil), do: nil
  defp parse_non_negative_int(value) when is_integer(value) and value >= 0, do: value

  defp parse_non_negative_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int >= 0 -> int
      _ -> nil
    end
  end

  defp parse_non_negative_int(_), do: nil

  defp parse_non_negative_number(nil), do: nil
  defp parse_non_negative_number(value) when is_integer(value) and value >= 0, do: value
  defp parse_non_negative_number(value) when is_float(value) and value >= 0, do: value

  defp parse_non_negative_number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} when number >= 0 -> number
      _ -> nil
    end
  end

  defp parse_non_negative_number(_), do: nil

  @spec completion_replace_range(term(), term()) :: term()
  defp completion_replace_range(content, cursor) when is_binary(content) and is_integer(cursor) do
    safe_cursor = min(max(cursor, 0), String.length(content))
    prefix = String.slice(content, 0, safe_cursor)
    match = Regex.run(~r/([A-Za-z_][A-Za-z0-9_']*)$/, prefix)
    token = if is_list(match), do: List.last(match), else: ""
    from = safe_cursor - String.length(token)
    {from, safe_cursor, token}
  end

  @spec maybe_put_state(term(), term(), term()) :: term()
  defp maybe_put_state(state, _key, nil), do: state
  defp maybe_put_state(state, key, value), do: Map.put(state, key, value)

  @spec sync_active_diagnostic_index_to_tab(term()) :: term()
  defp sync_active_diagnostic_index_to_tab(socket) do
    idx = socket.assigns[:active_diagnostic_index]

    update_active_tab(socket, fn tab ->
      state = tab.editor_state || %{}
      %{tab | editor_state: Map.put(state, :active_diagnostic_index, idx)}
    end)
  end

  @spec restore_editor_state(term(), term()) :: term()
  defp restore_editor_state(socket, state) when is_map(state) do
    cursor_offset = state[:cursor_offset] || 0
    scroll_top = state[:scroll_top] || 0
    scroll_left = state[:scroll_left] || 0

    push_event(socket, "token-editor-restore-state", %{
      cursor_offset: cursor_offset,
      scroll_top: scroll_top,
      scroll_left: scroll_left
    })
  end

  defp restore_editor_state(socket, _), do: socket

  @spec focus_diagnostic(term(), term()) :: term()
  defp focus_diagnostic(socket, direction) do
    diagnostics = socket.assigns.editor_inline_diagnostics

    if diagnostics == [] do
      socket
    else
      current = socket.assigns.active_diagnostic_index
      max_index = length(diagnostics) - 1

      next_index =
        case {direction, current} do
          {:next, nil} -> 0
          {:next, idx} when idx >= max_index -> 0
          {:next, idx} -> idx + 1
          {:prev, nil} -> max_index
          {:prev, 0} -> max_index
          {:prev, idx} -> idx - 1
        end

      diag = Enum.at(diagnostics, next_index)
      line = diag[:line]
      column = diag[:column] || 1

      if is_integer(line) and line > 0 do
        socket
        |> assign(:active_diagnostic_index, next_index)
        |> sync_active_diagnostic_index_to_tab()
        |> push_event("token-editor-focus", %{line: line, column: column})
      else
        socket
      end
    end
  end

  @spec normalize_active_diagnostic_index(term(), term()) :: term()
  defp normalize_active_diagnostic_index(nil, diagnostics),
    do: if(diagnostics == [], do: nil, else: 0)

  defp normalize_active_diagnostic_index(index, diagnostics)
       when is_integer(index) and index >= 0 do
    if index < length(diagnostics), do: index, else: nil
  end

  defp normalize_active_diagnostic_index(_index, diagnostics),
    do: if(diagnostics == [], do: nil, else: 0)

  @spec diagnostic_hits_token?(term(), term()) :: term()
  defp diagnostic_hits_token?(diag, token) do
    diag_line = diag[:line]
    token_line = token[:line]

    cond do
      !is_integer(diag_line) or diag_line != token_line ->
        false

      token.class == "whitespace" ->
        false

      is_integer(diag[:column]) and is_integer(token[:column]) and is_integer(token[:length]) ->
        diag_start = diag[:column]
        diag_end = if is_integer(diag[:end_column]), do: diag[:end_column], else: diag_start
        token_start = token.column
        token_end = token.column + max(token.length - 1, 0)
        ranges_overlap?(diag_start, diag_end, token_start, token_end)

      true ->
        true
    end
  end

  @spec ranges_overlap?(term(), term(), term(), term()) :: term()
  defp ranges_overlap?(a_start, a_end, b_start, b_end) do
    max(a_start, b_start) <= min(a_end, b_end)
  end

  @spec prepare_content_for_save(term(), term(), term(), term(), term(), term()) :: term()
  defp prepare_content_for_save(
         project,
         tab,
         auto_format_enabled,
         formatter_backend,
         parser_payload,
         tokens
       ) do
    disp = editor_source_display_path(tab.rel_path)

    if auto_format_enabled and elm_source_file?(tab.rel_path) do
      case format_source(project, tab, formatter_backend, parser_payload, tokens) do
        {:ok, result} ->
          message =
            if result.changed? do
              "Saved #{disp} and applied auto-format."
            else
              "Saved #{disp}"
            end

          status = if result.changed?, do: :applied, else: :unchanged

          {result.formatted_source, message, nil, %{status: status, rel_path: tab.rel_path}}

        {:error, reason} ->
          output =
            "Auto-format skipped on save. Saved unchanged source.\n#{inspect(reason)}"

          {tab.content, "Saved #{disp} (auto-format failed, kept original source).", output,
           %{status: :failed, rel_path: tab.rel_path}}
      end
    else
      {tab.content, "Saved #{disp}", nil, %{status: :inactive, rel_path: tab.rel_path}}
    end
  end

  @spec format_source(term(), term(), term(), term(), term()) :: term()
  defp format_source(project, tab, :elm_format, _parser_payload, _tokens) do
    ElmFormat.format(tab.content, cwd: source_root_path(project, tab.source_root))
  end

  defp format_source(_project, tab, _formatter_backend, parser_payload, tokens) do
    Formatter.format(tab.content,
      rel_path: tab.rel_path,
      parser_payload: parser_payload,
      tokens: tokens
    )
  end

  @spec source_root_path(term(), term()) :: String.t()
  defp source_root_path(project, source_root) do
    project
    |> Projects.project_workspace_path()
    |> Path.join(source_root)
  end

  @spec token_diagnostics_by_line(term()) :: term()
  defp token_diagnostics_by_line(diagnostics) do
    diagnostics
    |> Enum.filter(&is_integer(&1[:line]))
    |> Enum.group_by(& &1.line)
  end

  @spec inline_diagnostics(term(), term()) :: term()
  defp inline_diagnostics(diagnostics, lines) do
    diagnostics
    |> Enum.filter(&is_integer(&1[:line]))
    |> Enum.map(fn diag ->
      line = diag.line
      snippet = if line >= 1, do: Enum.at(lines, line - 1), else: nil
      Map.put(diag, :snippet, snippet)
    end)
  end
end
