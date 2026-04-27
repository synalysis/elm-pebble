defmodule IdeWeb.WorkspaceLive.EditorPage do
  @moduledoc false
  use IdeWeb, :html

  @protected_editor_rel_paths [
    "src/Main.elm",
    "src/CompanionApp.elm",
    "src/Companion/Types.elm",
    "src/Pebble/Ui/Resources.elm"
  ]

  @spec render(term()) :: term()
  def render(assigns) do
    ~H"""
    <section
      :if={@pane == :editor}
      class="relative grid min-h-0 flex-1 gap-4"
      style={editor_pane_grid_style(@editor_docs_panel_open, @editor_docs_col_px)}
    >
      <aside class="flex min-h-0 flex-col overflow-hidden rounded-lg border border-zinc-200 bg-white shadow-sm">
        <div class="min-h-0 flex-1 overflow-auto p-3">
          <h2 class="text-sm font-semibold">Files</h2>
          <p class="mt-1 text-[11px] text-zinc-500">Elm module files for each source root.</p>
          <div class="mt-3 space-y-3">
            <div :for={root <- editor_files_tree(@tree)}>
              <h3 class="mb-1 text-xs font-semibold uppercase tracking-wide text-zinc-500">
                {root.source_root}
              </h3>
              <.tree_nodes
                nodes={root.nodes}
                source_root={root.source_root}
                active_tab_id={@active_tab_id}
                opening_file_id={@opening_file_id}
                expanded_tree_dirs={@expanded_tree_dirs}
              />
            </div>
          </div>
        </div>
        <div class="shrink-0 space-y-2 border-t border-zinc-200 p-3">
          <p class="text-xs font-semibold uppercase tracking-wide text-zinc-500">Operations</p>
          <% active_editor_tab = active_tab(@tabs, @active_tab_id) %>
          <div class="flex flex-col gap-2">
            <button
              type="button"
              phx-click="open-create-file-modal"
              class="rounded bg-blue-600 px-3 py-2 text-xs font-medium text-white hover:bg-blue-700"
            >
              Create file…
            </button>
            <button
              type="button"
              phx-click="open-rename-file-modal"
              class="rounded bg-zinc-100 px-3 py-2 text-xs font-medium text-zinc-800 hover:bg-zinc-200 disabled:opacity-60"
              disabled={
                is_nil(active_editor_tab) or read_only_tab?(active_editor_tab) or
                  protected_editor_source_file?(active_editor_tab.rel_path)
              }
            >
              Rename active file…
            </button>
            <button
              type="button"
              phx-click="delete-file"
              data-confirm={
                if active_editor_tab do
                  "Delete #{editor_source_display_path(active_editor_tab.rel_path)}?"
                else
                  "Delete active file?"
                end
              }
              class="rounded bg-rose-100 px-3 py-2 text-xs font-medium text-rose-800 hover:bg-rose-200 disabled:opacity-60"
              disabled={
                is_nil(active_editor_tab) or read_only_tab?(active_editor_tab) or
                  protected_editor_source_file?(active_editor_tab.rel_path)
              }
            >
              Delete active file…
            </button>
          </div>
        </div>
      </aside>

      <main class="relative flex min-h-0 flex-col rounded-lg border border-zinc-200 bg-white p-3 shadow-sm">
        <div class="mb-3 flex flex-wrap items-center gap-2 border-b border-zinc-200 pb-2">
          <div class="flex min-w-0 flex-1 flex-wrap items-center gap-2">
            <button
              :for={tab <- @tabs}
              type="button"
              phx-click="select-tab"
              phx-value-id={tab.id}
              class={[
                "inline-flex items-center gap-1 rounded px-2 py-1 text-xs",
                @active_tab_id == tab.id && "bg-blue-100 text-blue-800",
                @active_tab_id != tab.id && "bg-zinc-100"
              ]}
            >
              <span>
                {editor_source_display_path(tab.rel_path)}{if tab.dirty, do: "*", else: ""}
              </span>
              <span
                phx-click="close-tab"
                phx-value-id={tab.id}
                class="cursor-pointer rounded bg-zinc-200 px-1 text-zinc-700"
              >
                x
              </span>
            </button>
          </div>
          <button
            type="button"
            phx-click="toggle-editor-docs-panel"
            class="shrink-0 rounded bg-zinc-100 px-3 py-2 text-sm font-medium text-zinc-800 hover:bg-zinc-200"
          >
            {if @editor_docs_panel_open, do: "Hide documentation", else: "Show documentation"}
          </button>
        </div>

        <div
          :if={active = active_tab(@tabs, @active_tab_id)}
          class="flex min-h-0 flex-1 flex-col space-y-3"
        >
          <div class="flex flex-wrap gap-2">
            <.button phx-click="save-file" disabled={active.read_only}>
              Save
            </.button>
            <.button phx-click="format-file" disabled={@format_status == :running or active.read_only}>
              {if @format_status == :running, do: "Formatting...", else: "Format"}
            </.button>
            <.link
              navigate={settings_path_with_return_to("/projects/#{@project.slug}/#{@pane}")}
              class="rounded bg-zinc-100 px-3 py-2 text-sm font-medium text-zinc-800"
            >
              Auto-format: {if @auto_format_on_save, do: "On", else: "Off"} · Mode: {String.upcase(
                Atom.to_string(@editor_mode)
              )}
            </.link>
            <span
              :if={@auto_format_last_result}
              class={[
                "inline-flex items-center rounded px-3 py-2 text-sm font-medium",
                auto_format_result_class(@auto_format_last_result.status)
              ]}
            >
              Last auto-format: {auto_format_result_label(@auto_format_last_result)}
            </span>
            <button
              type="button"
              phx-click="tokenize-active-file"
              class="rounded bg-zinc-100 px-3 py-2 text-sm font-medium text-zinc-800"
            >
              Refresh tokens
            </button>
          </div>
          <.form
            for={to_form(%{"content" => active.content}, as: :editor)}
            phx-change="editor-change"
            class="min-h-0 flex-1"
          >
            <div
              id={"token-editor-#{active.id}"}
              phx-hook="TokenEditor"
              phx-update="ignore"
              data-tokenize-idle-event="tokenize-compiler-idle"
              data-focus-next-event="focus-next-diagnostic"
              data-focus-prev-event="focus-prev-diagnostic"
              data-save-event="save-file"
              data-format-event="format-file"
              data-context-menu-event="editor-context-menu"
              data-tab-id={active.id}
              data-project-slug={@project.slug}
              data-source-root={active.source_root}
              data-rel-path={active.rel_path}
              data-editor-mode={Atom.to_string(@editor_mode)}
              data-editor-readonly={to_string(active.read_only)}
              data-editor-theme={Atom.to_string(@editor_theme)}
              data-editor-line-numbers={to_string(@editor_line_numbers)}
              data-editor-active-line-highlight={to_string(@editor_active_line_highlight)}
              data-restore-cursor-offset={editor_state_value(active.editor_state, :cursor_offset)}
              data-restore-scroll-top={editor_state_value(active.editor_state, :scroll_top)}
              data-restore-scroll-left={editor_state_value(active.editor_state, :scroll_left)}
              class="relative h-full min-h-[26rem] overflow-hidden rounded border border-zinc-800 bg-zinc-950"
            >
              <div data-role="cm-root" class="absolute inset-0"></div>
              <textarea
                data-role="input"
                name="editor[content]"
                spellcheck="false"
                readonly={active.read_only}
                class="sr-only"
              ><%= active.content %></textarea>
            </div>
          </.form>
          <p :if={active.read_only} class="text-xs text-zinc-500">
            This generated resources module is read-only.
          </p>
          <section :if={@debug_mode and @editor_inline_diagnostics != []} class="space-y-2">
            <h3 class="text-xs font-semibold uppercase tracking-wide text-zinc-500">
              Inline diagnostics
            </h3>
            <div class="flex items-center gap-2">
              <button
                type="button"
                phx-click="focus-prev-diagnostic"
                class="rounded bg-zinc-100 px-2 py-1 text-[11px] font-medium text-zinc-800 hover:bg-zinc-200"
              >
                Prev diagnostic
              </button>
              <button
                type="button"
                phx-click="focus-next-diagnostic"
                class="rounded bg-zinc-100 px-2 py-1 text-[11px] font-medium text-zinc-800 hover:bg-zinc-200"
              >
                Next diagnostic
              </button>
              <span class="text-[11px] text-zinc-600">Alt+ArrowUp / Alt+ArrowDown</span>
            </div>
            <ul class="space-y-2">
              <li
                :for={{diag, index} <- Enum.with_index(@editor_inline_diagnostics)}
                class={[
                  "rounded border px-3 py-2 text-xs",
                  @active_diagnostic_index == index &&
                    "border-amber-400 bg-amber-100 shadow-[0_0_0_1px_rgba(245,158,11,0.35)]",
                  @active_diagnostic_index != index && "border-amber-200 bg-amber-50"
                ]}
              >
                <p class="font-semibold text-amber-900">
                  {diag.severity} · line {diag.line || "?"}:{diag.column || "?"}
                </p>
                <p class="text-amber-900">{diag.message}</p>
                <p :if={diag.snippet} class="mt-1 truncate font-mono text-amber-800">
                  {diag.snippet}
                </p>
                <button
                  :if={diag.line}
                  type="button"
                  phx-click="jump-to-diagnostic"
                  phx-value-line={diag.line}
                  phx-value-column={diag[:column] || 1}
                  phx-value-index={index + 1}
                  class="mt-2 rounded bg-amber-100 px-2 py-1 text-[11px] font-medium text-amber-900 hover:bg-amber-200"
                >
                  Jump to location
                </button>
              </li>
            </ul>
          </section>
          <section :if={@debug_mode and @format_output} class="space-y-2">
            <h3 class="text-xs font-semibold uppercase tracking-wide text-zinc-500">
              Formatter
            </h3>
            <pre class="max-h-40 overflow-auto rounded border border-zinc-200 bg-zinc-50 p-2 text-xs text-zinc-700"><%= @format_output %></pre>
          </section>
        </div>
        <p :if={!active_tab(@tabs, @active_tab_id)} class="text-sm text-zinc-500">
          Open a file from the tree to start editing.
        </p>

        <section
          :if={!@editor_docs_panel_open and @debug_mode}
          class="mt-4 space-y-4 border-t border-zinc-200 pt-3"
        >
          <div>
            <h3 class="text-xs font-semibold uppercase tracking-wide text-zinc-500">Diagnostics</h3>
            <ul class="mt-2 max-h-48 space-y-2 overflow-auto">
              <li
                :for={item <- visible_diagnostics(@diagnostics, @debug_mode)}
                class="rounded border border-zinc-200 bg-zinc-50 p-2 text-xs"
              >
                <p class="font-semibold">{item.severity} · {item.source}</p>
                <p :if={item[:file]} class="font-mono text-[11px] text-zinc-600">
                  {item.file}:{item[:line] || "?"}:{item[:column] || "?"}
                </p>
                <p class="text-zinc-600">{item.message}</p>
              </li>
            </ul>
          </div>
          <div :if={@debug_mode}>
            <h3 class="text-xs font-semibold uppercase tracking-wide text-zinc-500">Tokenizer</h3>
            <div
              :if={@token_summary}
              class="mt-2 rounded border border-zinc-200 bg-zinc-50 p-2 text-xs"
            >
              <p>Total tokens: {@token_summary.total}</p>
              <p class="mt-1 text-zinc-600">mode: {tokenizer_mode_label(@tokenizer_mode)}</p>
            </div>
            <ul class="mt-2 max-h-32 space-y-2 overflow-auto">
              <li
                :for={diag <- @token_diagnostics}
                class="rounded border border-zinc-200 bg-zinc-50 p-2 text-xs"
              >
                <p class="font-semibold">{diag.severity} · {diag.source}</p>
                <p :if={diagnostic_position_label(diag)} class="font-mono text-[11px] text-zinc-600">
                  {diagnostic_position_label(diag)}
                </p>
                <p class="text-zinc-600">{diag.message}</p>
              </li>
            </ul>
          </div>
        </section>

        <div
          :if={@editor_context_menu}
          class="fixed z-[60] rounded-md border border-zinc-200 bg-white py-1 text-xs shadow-lg"
          style={"left: #{@editor_context_menu.x}px; top: #{@editor_context_menu.y}px;"}
        >
          <button
            type="button"
            phx-click="editor-context-open-docs"
            phx-value-offset={@editor_context_menu.offset}
            class="block w-full px-3 py-2 text-left hover:bg-zinc-100"
          >
            Open documentation
          </button>
          <button
            type="button"
            phx-click="editor-context-dismiss"
            class="block w-full px-3 py-2 text-left text-zinc-500 hover:bg-zinc-50"
          >
            Dismiss
          </button>
        </div>
      </main>

      <div
        :if={@editor_docs_panel_open}
        id="editor-docs-resizer"
        phx-hook="EditorDocsResizer"
        data-width={@editor_docs_col_px}
        data-min="200"
        data-max="720"
        class="group relative z-10 -mx-1 min-h-0 w-1.5 shrink-0 cursor-col-resize select-none rounded-full bg-zinc-200/80 hover:bg-sky-400/70"
        title="Drag to resize documentation panel"
      >
      </div>

      <aside
        :if={@editor_docs_panel_open}
        class="flex min-h-0 flex-col overflow-hidden rounded-lg border border-zinc-200 bg-white shadow-sm"
      >
        <div class="flex min-h-0 flex-1 flex-col overflow-hidden p-3">
          <div class="shrink-0">
            <h2 class="text-sm font-semibold">Documentation</h2>
            <p class="mt-1 text-[11px] text-zinc-600">
              Platform and <span class="font-mono">elm.json</span>
              packages. Manage dependencies on the
              <.link
                patch={~p"/projects/#{@project.slug}/packages"}
                class="font-medium text-blue-700 hover:underline"
              >
                Packages
              </.link>
              page.
            </p>

            <form id="editor-doc-package-form" phx-change="editor-doc-package" class="mt-3 block">
              <label class="block text-xs font-medium text-zinc-700">Package</label>
              <select
                name="doc_pkg"
                class="mt-1 w-full rounded border border-zinc-300 bg-white px-2 py-1.5 text-xs text-zinc-900"
              >
                <option
                  :for={row <- @editor_doc_packages}
                  value={row.package}
                  selected={row.package == @editor_doc_package}
                >
                  {row.label}
                </option>
              </select>
            </form>

            <form id="editor-doc-module-form" phx-change="editor-doc-module" class="mt-3 block">
              <label class="block text-xs font-medium text-zinc-700">Module</label>
              <div class="mt-2 block">
                <input
                  type="search"
                  name="doc_q"
                  value={@editor_doc_query}
                  placeholder="Search modules..."
                  class="w-full rounded border border-zinc-300 bg-white px-2 py-1.5 text-xs text-zinc-900"
                  phx-change="editor-doc-search"
                />
              </div>
              <select
                name="doc_mod"
                class="mt-1 w-full rounded border border-zinc-300 bg-white px-2 py-1.5 text-xs text-zinc-900 disabled:opacity-50"
                disabled={@editor_doc_package == nil}
              >
                <option value="">—</option>
                <option
                  :for={
                    mod <-
                      editor_doc_modules_for_package(
                        @editor_doc_packages,
                        @editor_doc_package,
                        @editor_doc_query
                      )
                  }
                  value={mod}
                  selected={mod == @editor_doc_module}
                >
                  {mod}
                </option>
              </select>
            </form>
          </div>

          <div class="ide-readme-markdown mt-3 min-h-0 flex-1 overflow-auto rounded border border-zinc-200 bg-white p-3">
            {raw(@editor_doc_html)}
          </div>
        </div>

        <div
          :if={@debug_mode}
          class="max-h-48 shrink-0 space-y-3 overflow-auto border-t border-zinc-200 p-3"
        >
          <div>
            <h3 class="text-xs font-semibold uppercase tracking-wide text-zinc-500">Diagnostics</h3>
            <ul class="mt-2 space-y-2">
              <li
                :for={item <- visible_diagnostics(@diagnostics, @debug_mode)}
                class="rounded border border-zinc-200 bg-zinc-50 p-2 text-xs"
              >
                <p class="font-semibold">{item.severity} · {item.source}</p>
                <p :if={item[:file]} class="font-mono text-[11px] text-zinc-600">
                  {item.file}:{item[:line] || "?"}:{item[:column] || "?"}
                </p>
                <p class="text-zinc-600">{item.message}</p>
                <p
                  :for={detail <- diagnostic_structured_lines(item)}
                  class="font-mono text-[11px] text-zinc-500"
                >
                  {detail}
                </p>
              </li>
            </ul>
          </div>
          <div :if={@debug_mode}>
            <h3 class="text-xs font-semibold uppercase tracking-wide text-zinc-500">Tokenizer</h3>
            <div
              :if={@token_summary}
              class="mt-2 rounded border border-zinc-200 bg-zinc-50 p-2 text-xs"
            >
              <p>Total tokens: {@token_summary.total}</p>
              <p class="mt-1 text-zinc-600">
                mode: {tokenizer_mode_label(@tokenizer_mode)}
              </p>
              <p class="mt-1 text-zinc-600">
                {Enum.map_join(@token_summary.classes, ", ", fn {klass, count} ->
                  "#{klass}=#{count}"
                end)}
              </p>
            </div>
            <ul class="mt-2 space-y-2">
              <li
                :for={diag <- @token_diagnostics}
                class="rounded border border-zinc-200 bg-zinc-50 p-2 text-xs"
              >
                <p class="font-semibold">{diag.severity} · {diag.source}</p>
                <p :if={diagnostic_position_label(diag)} class="font-mono text-[11px] text-zinc-600">
                  {diagnostic_position_label(diag)}
                </p>
                <p class="text-zinc-600">{diag.message}</p>
              </li>
            </ul>
          </div>
        </div>
      </aside>

      <div :if={@create_file_modal_open} class="fixed inset-0 z-50 grid place-items-center p-4">
        <div class="absolute inset-0 bg-black/40" phx-click="close-create-file-modal"></div>
        <div class="relative z-10 w-full max-w-md rounded-lg bg-white p-4 shadow-xl">
          <h3 class="text-sm font-semibold">Create file</h3>
          <.form for={@new_file_form} phx-submit="new-file" class="mt-3 space-y-2">
            <.input
              field={@new_file_form[:source_root]}
              type="select"
              label="Source root"
              options={@project.source_roots}
            />
            <.input
              field={@new_file_form[:rel_path]}
              type="text"
              label="New file path"
              placeholder="Example.elm"
            />
            <p class="text-xs text-zinc-500">
              Use a `.elm` file path where each module segment starts with a capital letter (example: `Pages/Home.elm`).
            </p>
            <div class="flex justify-end gap-2 pt-2">
              <button
                type="button"
                phx-click="close-create-file-modal"
                class="rounded px-3 py-2 text-xs text-zinc-600"
              >
                Cancel
              </button>
              <.button>Create file</.button>
            </div>
          </.form>
        </div>
      </div>

      <div :if={@rename_file_modal_open} class="fixed inset-0 z-50 grid place-items-center p-4">
        <div class="absolute inset-0 bg-black/40" phx-click="close-rename-file-modal"></div>
        <div class="relative z-10 w-full max-w-md rounded-lg bg-white p-4 shadow-xl">
          <h3 class="text-sm font-semibold">Rename active file</h3>
          <.form for={@rename_form} phx-submit="rename-file" class="mt-3 space-y-2">
            <.input
              field={@rename_form[:new_rel_path]}
              type="text"
              label="New path"
              placeholder="MainRenamed.elm"
            />
            <div class="flex justify-end gap-2 pt-2">
              <button
                type="button"
                phx-click="close-rename-file-modal"
                class="rounded px-3 py-2 text-xs text-zinc-600"
              >
                Cancel
              </button>
              <.button>Rename</.button>
            </div>
          </.form>
        </div>
      </div>
    </section>
    """
  end

  attr(:nodes, :list, required: true)
  attr(:source_root, :string, required: true)
  attr(:active_tab_id, :string, default: nil)
  attr(:opening_file_id, :string, default: nil)
  attr(:expanded_tree_dirs, :any, default: nil)

  @spec tree_nodes(term()) :: term()
  defp tree_nodes(assigns) do
    ~H"""
    <ul class="space-y-1 text-sm">
      <li :for={node <- @nodes}>
        <%= if node.type == :dir do %>
          <details open={
            tree_contains_tab?(
              node,
              @source_root,
              @active_tab_id,
              @opening_file_id,
              @expanded_tree_dirs
            )
          }>
            <summary
              class="cursor-pointer text-zinc-700"
              phx-click="toggle-tree-dir"
              phx-value-source-root={@source_root}
              phx-value-rel-path={node.rel_path}
            >
              {node.name}
            </summary>
            <div class="ml-3 mt-1 border-l border-zinc-200 pl-2">
              <.tree_nodes
                nodes={node.children}
                source_root={@source_root}
                active_tab_id={@active_tab_id}
                opening_file_id={@opening_file_id}
                expanded_tree_dirs={@expanded_tree_dirs}
              />
            </div>
          </details>
        <% else %>
          <% file_id = tab_id(@source_root, node.rel_path) %>
          <button
            type="button"
            class={[
              "w-full rounded px-2 py-1 text-left",
              @active_tab_id == file_id && "bg-blue-600 text-white",
              @active_tab_id != file_id && "hover:bg-zinc-100"
            ]}
            phx-click="open-file"
            phx-value-source-root={@source_root}
            phx-value-rel-path={node.rel_path}
            disabled={@opening_file_id == file_id}
          >
            {node.name}
            <span :if={@opening_file_id == file_id} class="ml-2 text-[11px] text-blue-200">
              Opening...
            </span>
          </button>
        <% end %>
      </li>
    </ul>
    """
  end

  @spec tree_contains_tab?(term(), term(), term(), term(), term()) :: term()
  defp tree_contains_tab?(
         %{type: :file, rel_path: rel_path},
         source_root,
         active_tab_id,
         opening_file_id,
         _expanded_tree_dirs
       )
       when is_binary(rel_path) and is_binary(source_root) do
    id = tab_id(source_root, rel_path)
    id == active_tab_id or id == opening_file_id
  end

  defp tree_contains_tab?(
         %{type: :dir, rel_path: rel_path, children: children},
         source_root,
         active_tab_id,
         opening_file_id,
         expanded_tree_dirs
       )
       when is_list(children) and is_binary(source_root) and is_binary(rel_path) do
    key = tree_dir_key(source_root, rel_path)

    MapSet.member?(expanded_tree_dirs || MapSet.new(), key) or
      Enum.any?(
        children,
        &tree_contains_tab?(&1, source_root, active_tab_id, opening_file_id, expanded_tree_dirs)
      )
  end

  defp tree_contains_tab?(_, _, _, _, _), do: false

  @spec tree_dir_key(term(), term()) :: String.t()
  defp tree_dir_key(source_root, rel_path), do: "#{source_root}:#{rel_path}"

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

  @spec active_tab(term(), term()) :: term()
  defp active_tab(tabs, active_tab_id), do: Enum.find(tabs, &(&1.id == active_tab_id))

  @spec tab_id(term(), term()) :: term()
  defp tab_id(source_root, rel_path), do: "#{source_root}:#{rel_path}"

  @spec read_only_tab?(term()) :: term()
  defp read_only_tab?(%{read_only: true}), do: true
  defp read_only_tab?(_), do: false

  defp editor_state_value(state, key) when is_map(state) do
    Map.get(state, key, 0) || 0
  end

  defp editor_state_value(_state, _key), do: 0

  @spec protected_editor_source_file?(term()) :: term()
  defp protected_editor_source_file?(rel_path) when is_binary(rel_path),
    do: rel_path in @protected_editor_rel_paths

  defp protected_editor_source_file?(_), do: false

  @spec editor_pane_grid_style(term(), term()) :: term()
  defp editor_pane_grid_style(true, px) when is_integer(px) do
    "grid-template-columns: 16rem minmax(0, 1fr) 6px #{px}px; min-height: 0;"
  end

  defp editor_pane_grid_style(false, _px) do
    "grid-template-columns: 16rem minmax(0, 1fr); min-height: 0;"
  end

  @spec editor_files_tree(term()) :: term()
  defp editor_files_tree(tree) when is_list(tree) do
    Enum.map(tree, fn %{source_root: source_root, nodes: nodes} ->
      src_children =
        case Enum.find(nodes, &(&1.type == :dir and &1.name == "src")) do
          %{children: children} when is_list(children) -> children
          _ -> []
        end

      src_children =
        if source_root == "protocol" do
          flatten_protocol_companion_dir(src_children)
        else
          src_children
        end

      %{source_root: source_root, nodes: src_children}
    end)
  end

  # Protocol modules live under src/Companion/…; show them at the Files root without a Companion folder.
  @spec flatten_protocol_companion_dir(term()) :: term()
  defp flatten_protocol_companion_dir(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, fn
      %{type: :dir, name: "Companion", children: kids} when is_list(kids) -> kids
      other -> [other]
    end)
  end

  @spec editor_source_display_path(term()) :: term()
  defp editor_source_display_path("src/" <> rest), do: rest
  defp editor_source_display_path(rel) when is_binary(rel), do: rel

  @spec settings_path_with_return_to(term()) :: term()
  defp settings_path_with_return_to(return_to) when is_binary(return_to) do
    "/settings?return_to=#{URI.encode_www_form(return_to)}"
  end

  @spec tokenizer_mode_label(term()) :: term()
  defp tokenizer_mode_label(:compiler), do: "elmc"
  defp tokenizer_mode_label(:fast), do: "fast"
  defp tokenizer_mode_label(:plain), do: "plain"
  defp tokenizer_mode_label(_), do: "fast"

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

  @spec visible_diagnostics(term(), term()) :: term()
  defp visible_diagnostics(diagnostics, true) when is_list(diagnostics), do: diagnostics

  defp visible_diagnostics(diagnostics, false) when is_list(diagnostics) do
    Enum.reject(diagnostics, fn diag ->
      source =
        diag[:source] ||
          diag["source"] ||
          ""

      source == "tokenizer"
    end)
  end

  defp visible_diagnostics(_diagnostics, _debug_mode), do: []

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

  @spec diagnostic_position_label(term()) :: term()
  defp diagnostic_position_label(diag) do
    line = diag[:line]
    column = diag[:column]
    end_line = diag[:end_line]
    end_column = diag[:end_column]

    cond do
      is_integer(line) and is_integer(column) and is_integer(end_line) and is_integer(end_column) and
          (line != end_line or column != end_column) ->
        "line #{line}:#{column} - #{end_line}:#{end_column}"

      is_integer(line) and is_integer(column) ->
        "line #{line}:#{column}"

      is_integer(line) ->
        "line #{line}"

      true ->
        nil
    end
  end

  @spec auto_format_result_label(term()) :: term()
  defp auto_format_result_label(%{status: :applied, rel_path: rel_path}),
    do: "Applied to #{editor_source_display_path(rel_path)}"

  defp auto_format_result_label(%{status: :unchanged, rel_path: rel_path}),
    do: "No changes for #{editor_source_display_path(rel_path)}"

  defp auto_format_result_label(%{status: :failed, rel_path: rel_path}),
    do: "Skipped (parse failure) for #{editor_source_display_path(rel_path)}"

  defp auto_format_result_label(%{status: :inactive, rel_path: rel_path}),
    do: "Not active for #{editor_source_display_path(rel_path)}"

  @spec auto_format_result_class(term()) :: term()
  defp auto_format_result_class(:applied), do: "bg-emerald-100 text-emerald-800"
  defp auto_format_result_class(:unchanged), do: "bg-blue-100 text-blue-800"
  defp auto_format_result_class(:failed), do: "bg-amber-100 text-amber-900"
  defp auto_format_result_class(:inactive), do: "bg-zinc-100 text-zinc-700"
end
