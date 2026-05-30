defmodule IdeWeb.WorkspaceLive.EditorFlow do
  @moduledoc """
  Editor pane LiveView events and async handlers extracted from `WorkspaceLive`.

  File tree, tabs, editor input, docs panel, diagnostics navigation, and related
  `handle_async` work (`:open_file`, `:editor_check`, `:format_file`, dependency refresh).
  """

  import Phoenix.Component, only: [assign: 2, assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [put_flash: 3, push_event: 3, start_async: 3]

  alias Ide.EditorCompletion
  alias Ide.EditorDocLinks
  alias Ide.Formatter
  alias Ide.Formatter.EditPatch
  alias Ide.Projects
  alias Ide.Resources.ResourceStore
  alias IdeWeb.WorkspaceLive.BuildFlow
  alias IdeWeb.WorkspaceLive.DebuggerFlow
  alias IdeWeb.WorkspaceLive.DebuggerSupport
  alias IdeWeb.WorkspaceLive.EditorSupport

  @type socket :: Phoenix.LiveView.Socket.t()
  @type lv_noreply :: {:noreply, socket()}

  @editor_events ~w(
    editor-change
    editor-key-edit
    editor-request-completions
    editor-submit
    format-file
    save-file
    editor-context-menu
    editor-context-dismiss
    editor-context-open-docs
    toggle-editor-docs-panel
    set-editor-docs-width
    editor-doc-package
    editor-doc-module
    editor-doc-search
    editor-state-changed
    tokenize-active-file
    tokenize-compiler-idle
    jump-to-diagnostic
    focus-next-diagnostic
    focus-prev-diagnostic
  )

  @file_tab_events ~w(
    open-file
    toggle-tree-dir
    new-file
    select-tab
    close-tab
    rename-file
    delete-file
    open-create-file-modal
    close-create-file-modal
    open-rename-file-modal
    close-rename-file-modal
    add-companion-app
  )

  @editor_asyncs [:open_file, :editor_check, :format_file, :refresh_editor_dependencies, :refresh_editor_dependency_usage]

  @spec editor_events() :: [String.t()]
  def editor_events, do: @editor_events

  @spec file_tab_events() :: [String.t()]
  def file_tab_events, do: @file_tab_events

  @spec editor_asyncs() :: [atom()]
  def editor_asyncs, do: @editor_asyncs

  @spec handles?(String.t()) :: boolean()
  def handles?(event) when is_binary(event),
    do: event in @editor_events or event in @file_tab_events

  @spec handle_event(String.t(), map(), socket()) :: lv_noreply()
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
                   tab_content(next_active),
                   tab_rel_path(next_active)
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
       tab_content(selected_tab),
       tab_rel_path(selected_tab)
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
       tab_content(next_active),
       tab_rel_path(next_active)
     )
     |> restore_editor_state(next_state)}
  end

  def handle_event("editor-change", %{"editor" => %{"content" => content}}, socket) do
    active = active_tab(socket)
    active_rel_path = tab_rel_path(active)

    cond do
      read_only_tab?(active) ->
        {:noreply, socket}

      active && active.content == content ->
        {:noreply, socket}

      true ->
        {:noreply,
         socket
         |> update_tab(&apply_editor_content(&1, content))
         |> assign_tokenization(content, active_rel_path)
         |> clear_editor_check(active)}
    end
  end

  def handle_event("editor-change", %{"content" => content}, socket) do
    active = active_tab(socket)
    active_rel_path = tab_rel_path(active)

    cond do
      read_only_tab?(active) ->
        {:noreply, socket}

      active && active.content == content ->
        {:noreply, socket}

      true ->
        {:noreply,
         socket
         |> update_tab(&apply_editor_content(&1, content))
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
      active_rel_path = tab_rel_path(active)
      next_content = apply_text_patch(content, edit_result)

      {:noreply,
       socket
       |> update_tab(&apply_editor_content(&1, next_content))
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
    __MODULE__.handle_event("format-file", params, socket)
  end

  def handle_event("editor-submit", params, socket) do
    __MODULE__.handle_event("save-file", params, socket)
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
                |> update_tab(fn active -> mark_editor_content_saved(active, content_to_save) end)
                |> assign(:format_output, format_output)
                |> assign(:auto_format_last_result, auto_format_last_result)
                |> assign_tokenization(content_to_save, tab.rel_path, mode: :compiler)

              socket =
                if DebuggerFlow.debugger_session_active?(socket) do
                  schedule_compiler_check(socket)
                else
                  socket
                end

              socket = schedule_editor_check(socket, tab)

              socket =
                if capability_sync_source?(tab.source_root, tab.rel_path) do
                  refresh_detected_capabilities(socket)
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

  defp do_handle_async(:open_file, {:ok, {{:ok, contents}, token, source_root, rel_path}}, socket) do
    if socket.assigns.file_open_token == token do
      editor_state = default_editor_state()

      tab = %{
        id: tab_id(source_root, rel_path),
        source_root: source_root,
        rel_path: rel_path,
        content: contents,
        saved_content: contents,
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

  defp do_handle_async(:open_file, {:ok, {{:error, reason}, token, _source_root, _rel_path}}, socket) do
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

  defp do_handle_async(:open_file, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:opening_file_id, nil)
     |> assign(:opening_file_label, nil)
     |> assign(:file_open_token, nil)
     |> put_flash(:error, "Failed to open file: #{inspect(reason)}")}
  end

  defp do_handle_async(:refresh_editor_dependency_usage, {:ok, {payload, token}}, socket) do
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

  defp do_handle_async(:refresh_editor_dependency_usage, {:exit, _reason}, socket) do
    {:noreply, socket}
  end

  defp do_handle_async(:refresh_editor_dependencies, {:ok, {payload, token}}, socket) do
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

  defp do_handle_async(:refresh_editor_dependencies, {:exit, _reason}, socket) do
    {:noreply, socket}
  end

  defp do_handle_async(:editor_check, {:ok, {{:ok, result}, token, source_root, rel_path}}, socket) do
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

  defp do_handle_async(:editor_check, {:ok, {{:error, reason}, token, source_root, rel_path}}, socket) do
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

  defp do_handle_async(:editor_check, {:exit, reason}, socket) do
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

  defp do_handle_async(:run_build, result, socket),
    do: BuildFlow.handle_async(:run_build, result, socket)

  defp do_handle_async(:run_compile, result, socket),
    do: BuildFlow.handle_async(:run_compile, result, socket)

  defp do_handle_async(:run_manifest, result, socket),
    do: BuildFlow.handle_async(:run_manifest, result, socket)

  defp do_handle_async(
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
          mark_editor_content_saved(active, result.formatted_source)
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

  defp do_handle_async(
        :format_file,
        {:ok, {:ok, %{tab: _tab, write_result: {:error, reason}}}},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:format_status, :error)
     |> assign(:format_output, "Format completed but save failed: #{inspect(reason)}")}
  end

  defp do_handle_async(:format_file, {:ok, {:error, %{reason: reason}}}, socket) do
    {:noreply,
     socket
     |> assign(:format_status, :error)
     |> assign(:format_output, render_format_error(reason))}
  end

  defp do_handle_async(:format_file, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:format_status, :error)
     |> assign(:format_output, render_format_error(reason))}
  end

  defp do_handle_async(:format_file, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:format_status, :error)
     |> assign(:format_output, "Format task exited: #{inspect(reason)}")}
  end

  @spec handle_async(atom(), term(), socket()) :: lv_noreply()
  def handle_async(async, result, socket) when async in @editor_asyncs do
    do_handle_async(async, result, socket)
  end

  def handle_async(_async, _result, socket), do: {:noreply, socket}

  defdelegate active_tab(socket), to: EditorSupport
  defdelegate active_tab(tabs, active_tab_id), to: EditorSupport
  defdelegate read_only_tab?(tab), to: EditorSupport
  defdelegate ensure_can_modify_editor_file(tab), to: EditorSupport
  defdelegate update_tab(socket, updater), to: EditorSupport
  defdelegate update_tab_by_id(socket, tab_id, updater), to: EditorSupport
  defdelegate refresh_tab_read_only(tab), to: EditorSupport
  defdelegate tab_content(tab), to: EditorSupport
  defdelegate tab_rel_path(tab), to: EditorSupport
  defdelegate tab_with_save_content(tab, params), to: EditorSupport
  defdelegate refresh_tree(socket), to: EditorSupport
  defdelegate editor_source_display_path(rel_path), to: EditorSupport
  defdelegate editor_file_tree_label(source_root, rel_path), to: EditorSupport
  defdelegate normalize_editor_src_rel_path(path), to: EditorSupport
  defdelegate module_name_from_rel_path(rel_path), to: EditorSupport
  defdelegate validate_new_elm_module_name(module_name), to: EditorSupport
  defdelegate new_elm_module_template(module_name), to: EditorSupport
  defdelegate creatable_source_roots(project), to: EditorSupport
  defdelegate validate_creatable_source_root(project, source_root), to: EditorSupport
  defdelegate tab_id(source_root, rel_path), to: EditorSupport
  defdelegate apply_editor_content(tab, content), to: EditorSupport
  defdelegate mark_editor_content_saved(tab, content), to: EditorSupport
  defdelegate tree_dir_key(source_root, rel_path), to: EditorSupport
  defdelegate apply_text_patch(content, edit_patch), to: EditorSupport
  defdelegate identity_edit_patch(content, start_offset, end_offset), to: EditorSupport
  defdelegate semantic_edit_ops_enabled?(), to: EditorSupport
  defdelegate render_format_output(result), to: EditorSupport
  defdelegate formatted_cursor_offset(socket, formatted_source), to: EditorSupport
  defdelegate render_format_error(reason), to: EditorSupport
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
  defdelegate format_source(project, tab, formatter_backend, parser_payload, tokens), to: EditorSupport
  defdelegate prepare_content_for_save(project, tab, auto_format_enabled, formatter_backend, parser_payload, tokens), to: EditorSupport
  defdelegate default_editor_state(), to: EditorSupport
  defdelegate update_editor_state_tab(socket, tab_id, updater), to: EditorSupport
  defdelegate clear_editor_check(socket, tab), to: EditorSupport
  defdelegate schedule_editor_check(socket, tab), to: EditorSupport
  defdelegate load_editor_doc_body(socket, package, version, module), to: EditorSupport
  defdelegate apply_doc_catalog_rows(socket, rows), to: EditorSupport
  defdelegate maybe_regenerate_phone_preferences_after_save(socket, tab), to: EditorSupport
  defdelegate capability_sync_source?(source_root, rel_path), to: EditorSupport
  defdelegate refresh_detected_capabilities(socket), to: EditorSupport
  defdelegate push_editor_check_lint_diagnostics(socket, source_root, rel_path, diagnostics), to: EditorSupport
  defdelegate schedule_compiler_check(socket), to: BuildFlow
end
