defmodule IdeWeb.WorkspaceLive.EditorPage do
  @moduledoc false
  use IdeWeb, :html

  alias Ide.Resources.ResourceStore

  alias Phoenix.LiveView.Rendered

  @type pane ::
          :editor
          | :build
          | :debugger
          | :emulator
          | :publish
          | :settings
          | :resources
          | :packages
          | atom()
  @type assigns :: map()
  @type rendered :: Rendered.t()
  @type tab :: map()
  @type tree_node :: map()
  @type diagnostic :: Ide.Compiler.diagnostic() | map()

  @protected_editor_rel_paths [
    "src/Main.elm",
    "src/Companion/Types.elm",
    "src/Companion/GeneratedPreferences.elm",
    "src/Pebble/Ui/Resources.elm"
  ]

  @spec render(assigns()) :: rendered()
  def render(assigns) do
    ~H"""
    <.editor_workspace {assigns} />
    """
  end

  attr(:pane, :atom, required: true)
  attr(:tree, :list, required: true)
  attr(:tabs, :list, required: true)
  attr(:active_tab_id, :any, default: nil)
  attr(:opening_file_id, :any, default: nil)
  attr(:expanded_tree_dirs, :any, default: nil)
  attr(:editor_docs_panel_open, :boolean, required: true)
  attr(:editor_docs_col_px, :integer, required: true)
  attr(:companion_app_present, :boolean, required: true)
  attr(:project, :map, required: true)
  attr(:rename_file_modal_open, :boolean, required: true)
  attr(:rename_form, :any, required: true)
  attr(:create_file_modal_open, :boolean, required: true)
  attr(:new_file_form, :any, required: true)
  attr(:create_file_source_roots, :list, default: [])
  attr(:editor_context_menu, :any, default: nil)
  attr(:editor_check_status, :atom, default: nil)
  attr(:editor_check_output, :any, default: nil)
  attr(:editor_inline_diagnostics, :list, default: [])
  attr(:active_diagnostic_index, :any, default: nil)
  attr(:editor_doc_packages, :list, default: [])
  attr(:editor_doc_package, :any, default: nil)
  attr(:editor_doc_module, :string, default: "")
  attr(:editor_doc_html, :string, default: "")
  attr(:editor_doc_query, :string, default: "")
  attr(:editor_tokenizer_mode, :atom, default: :fast)
  attr(:editor_tokens, :list, default: [])
  attr(:editor_fold_ranges, :list, default: [])
  attr(:editor_line_count, :integer, default: 1)
  attr(:editor_token_diag_by_line, :map, default: %{})
  attr(:editor_parser_panel, :any, default: nil)
  attr(:editor_parser_payload, :any, default: nil)
  attr(:editor_check_token, :any, default: nil)
  attr(:editor_check_source_root, :any, default: nil)
  attr(:editor_check_rel_path, :any, default: nil)
  attr(:editor_deps_panel_open, :boolean, default: false)
  attr(:packages_target_root, :string, default: "watch")
  attr(:project_elm_direct, :list, default: [])
  attr(:project_elm_indirect, :list, default: [])
  attr(:editor_deps_usage_refresh_token, :any, default: nil)
  attr(:editor_deps_docs_refresh_token, :any, default: nil)
  attr(:format_status, :any, default: nil)
  attr(:debug_mode, :boolean, default: false)
  attr(:auto_format_on_save, :boolean, default: false)
  attr(:editor_mode, :atom, default: :default)
  attr(:editor_theme, :atom, default: :light)
  attr(:editor_line_numbers, :boolean, default: true)
  attr(:editor_active_line_highlight, :boolean, default: true)
  attr(:editor_check_diagnostics, :list, default: [])
  attr(:format_output, :any, default: nil)
  attr(:token_summary, :any, default: nil)
  attr(:tokenizer_mode, :atom, default: :fast)
  attr(:token_diagnostics, :list, default: [])
  attr(:myself, :any, default: nil)

  @spec editor_workspace(assigns()) :: rendered()
  defp editor_workspace(assigns) do
    ~H"""
    <%= if @pane == :editor do %>
      <section
        class="relative grid min-h-0 flex-1 gap-4"
        style={editor_pane_style(@editor_docs_panel_open, @editor_docs_col_px)}
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
                :if={!@companion_app_present}
                type="button"
                phx-click="add-companion-app"
                class="rounded bg-emerald-100 px-3 py-2 text-xs font-medium text-emerald-900 hover:bg-emerald-200"
              >
                Add companion app
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
            class="flex min-h-0 flex-1 flex-col gap-3 overflow-hidden"
          >
            <% editor_check_visible =
              editor_check_visible?(
                @editor_check_status,
                @editor_check_source_root,
                @editor_check_rel_path,
                @editor_check_diagnostics,
                active
              ) %>

            <div class="flex flex-wrap gap-2">
              <.button
                type="submit"
                form={"token-editor-form-#{active.id}"}
                name="editor_action"
                value="save"
                disabled={editor_read_only?(active)}
              >
                Save
              </.button>
              <.button
                type="submit"
                form={"token-editor-form-#{active.id}"}
                name="editor_action"
                value="format"
                disabled={@format_status == :running or editor_read_only?(active)}
              >
                {if @format_status == :running, do: "Formatting...", else: "Format"}
              </.button>
              <.link
                navigate={settings_path_with_return_to("/projects/#{@project.slug}/#{@pane}")}
                class="rounded bg-zinc-100 px-3 py-2 text-sm font-medium text-zinc-800"
              >
                Auto-format: {if @auto_format_on_save, do: "On", else: "Off"}
              </.link>
              <button
                :if={@debug_mode}
                type="button"
                phx-click="tokenize-active-file"
                class="rounded bg-zinc-100 px-3 py-2 text-sm font-medium text-zinc-800"
              >
                Refresh tokens
              </button>
              <span
                :if={
                  editor_check_running_for_active?(
                    @editor_check_status,
                    @editor_check_source_root,
                    @editor_check_rel_path,
                    active
                  )
                }
                class="inline-flex items-center rounded bg-blue-50 px-3 py-2 text-sm font-medium text-blue-800"
              >
                Checking saved file…
              </span>
            </div>
            <.form
              for={to_form(%{"content" => active.content}, as: :editor)}
              id={"token-editor-form-#{active.id}"}
              phx-change="editor-change"
              phx-submit="editor-submit"
              class={[
                "flex-1",
                editor_check_visible && "min-h-0",
                !editor_check_visible && "min-h-[26rem]"
              ]}
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
                data-editor-readonly={to_string(editor_read_only?(active))}
                data-editor-theme={Atom.to_string(@editor_theme)}
                data-editor-line-numbers={to_string(@editor_line_numbers)}
                data-editor-active-line-highlight={to_string(@editor_active_line_highlight)}
                data-restore-cursor-offset={editor_state_value(active.editor_state, :cursor_offset)}
                data-restore-scroll-top={editor_state_value(active.editor_state, :scroll_top)}
                data-restore-scroll-left={editor_state_value(active.editor_state, :scroll_left)}
                class="relative h-full min-h-0 overflow-hidden rounded border border-zinc-800 bg-zinc-950"
              >
                <div data-role="cm-root" class="absolute inset-0"></div>
                <textarea
                  data-role="input"
                  name="editor[content]"
                  spellcheck="false"
                  readonly={editor_read_only?(active)}
                  class="sr-only"
                ><%= active.content %></textarea>
              </div>
            </.form>
            <p :if={editor_read_only?(active)} class="text-xs text-zinc-500">
              This generated file is read-only.
            </p>
            <section
              :if={editor_check_visible}
              class="flex max-h-72 shrink-0 flex-col overflow-hidden rounded border border-rose-200 bg-rose-50 p-3 text-sm text-rose-950"
            >
              <div class="flex flex-wrap items-center justify-between gap-2">
                <h3 class="font-semibold">Compile errors</h3>
                <span class="text-xs text-rose-800">
                  {editor_check_engine_label(@editor_check_source_root)} · {editor_source_display_path(
                    @editor_check_rel_path || active.rel_path
                  )}
                </span>
              </div>
              <ul
                :if={@editor_check_diagnostics != []}
                class="mt-3 min-h-0 space-y-2 overflow-auto pr-1"
              >
                <li
                  :for={{diag, index} <- Enum.with_index(@editor_check_diagnostics)}
                  phx-click={if diagnostic_editor_jumpable?(diag, active), do: "jump-to-diagnostic"}
                  phx-value-line={phx_value_int(diagnostic_line(diag))}
                  phx-value-column={phx_value_int(diagnostic_column(diag) || 1)}
                  phx-value-index={phx_value_int(index + 1)}
                  class={[
                    "rounded border border-rose-200 bg-white/70 px-3 py-2",
                    diagnostic_editor_jumpable?(diag, active) &&
                      "cursor-pointer transition hover:border-rose-300 hover:bg-white focus:outline-none focus:ring-2 focus:ring-rose-300"
                  ]}
                  tabindex={if diagnostic_editor_jumpable?(diag, active), do: "0"}
                  role={if diagnostic_editor_jumpable?(diag, active), do: "button"}
                >
                  <p class="text-xs font-semibold uppercase tracking-wide text-rose-700">
                    {diag.severity} · {diag.source}
                    <span :if={diagnostic_file_position_label(diag)} class="font-mono normal-case">
                      · {diagnostic_file_position_label(diag)}
                    </span>
                  </p>
                  <p class="mt-1 whitespace-pre-wrap text-sm">{diag.message}</p>
                  <p
                    :if={diagnostic_editor_jumpable?(diag, active)}
                    class="mt-2 text-xs font-medium text-rose-800"
                  >
                    Click to jump to this location
                  </p>
                </li>
              </ul>
              <pre
                :if={@editor_check_diagnostics == [] and @editor_check_output}
                class="mt-3 max-h-56 overflow-auto rounded bg-rose-950 p-3 text-xs text-rose-50"
              ><%= @editor_check_output %></pre>
            </section>
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
                    phx-value-line={phx_value_int(diag.line)}
                    phx-value-column={phx_value_int(diag[:column] || 1)}
                    phx-value-index={phx_value_int(index + 1)}
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
            class="fixed z-[60] min-w-[12rem] rounded-md border border-zinc-200 bg-white py-1 text-xs shadow-lg"
            style={"left: #{@editor_context_menu.x}px; top: #{@editor_context_menu.y}px;"}
          >
            <.editor_context_menu_item action="cut" label="Cut" shortcut="Ctrl+X" readonly={@editor_context_menu.readonly} />
            <.editor_context_menu_item action="copy" label="Copy" shortcut="Ctrl+C" />
            <.editor_context_menu_item action="paste" label="Paste" shortcut="Ctrl+V" readonly={@editor_context_menu.readonly} />
            <div class="my-1 border-t border-zinc-200" />
            <.editor_context_menu_item action="undo" label="Undo" shortcut="Ctrl+Z" />
            <.editor_context_menu_item action="redo" label="Redo" shortcut="Ctrl+Shift+Z" />
            <div class="my-1 border-t border-zinc-200" />
            <.editor_context_menu_item action="select-all" label="Select all" shortcut="Ctrl+A" />
            <div class="my-1 border-t border-zinc-200" />
            <.editor_context_menu_item
              action="format"
              label="Format document"
              shortcut="Shift+Alt+F"
              readonly={@editor_context_menu.readonly}
            />
            <.editor_context_menu_item
              action="save"
              label="Save"
              shortcut="Ctrl+S"
              readonly={@editor_context_menu.readonly}
            />
            <div class="my-1 border-t border-zinc-200" />
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
                options={@create_file_source_roots}
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
    <% end %>
    """
  end

  attr(:action, :string, required: true)
  attr(:label, :string, required: true)
  attr(:shortcut, :string, default: nil)
  attr(:readonly, :boolean, default: false)

  defp editor_context_menu_item(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="editor-context-action"
      phx-value-action={@action}
      disabled={@readonly}
      class={[
        "flex w-full items-center justify-between gap-4 px-3 py-2 text-left",
        @readonly && "cursor-not-allowed text-zinc-400",
        !@readonly && "hover:bg-zinc-100"
      ]}
    >
      <span>{@label}</span>
      <span :if={@shortcut} class="text-[10px] text-zinc-400">{@shortcut}</span>
    </button>
    """
  end

  attr(:nodes, :list, required: true)
  attr(:source_root, :string, required: true)
  attr(:active_tab_id, :any, default: nil)
  attr(:opening_file_id, :any, default: nil)
  attr(:expanded_tree_dirs, :any, default: nil)

  @spec tree_nodes(assigns()) :: rendered()
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

  @spec tree_contains_tab?(
          tree_node(),
          String.t(),
          String.t() | nil,
          String.t() | nil,
          MapSet.t() | nil
        ) :: boolean()
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

  @spec tree_dir_key(String.t(), String.t()) :: String.t()
  defp tree_dir_key(source_root, rel_path), do: "#{source_root}:#{rel_path}"

  @spec editor_doc_modules_for_package([map()], String.t(), String.t()) :: [String.t()]
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

  @spec filter_editor_doc_modules([String.t()], String.t()) :: [String.t()]
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

  @spec active_tab([tab()], String.t() | nil) :: tab() | nil
  defp active_tab(tabs, active_tab_id), do: Enum.find(tabs, &(&1.id == active_tab_id))

  @spec tab_id(String.t(), String.t()) :: String.t()
  defp tab_id(source_root, rel_path), do: "#{source_root}:#{rel_path}"

  @spec read_only_tab?(tab() | nil) :: boolean()
  defp read_only_tab?(%{source_root: source_root, rel_path: rel_path})
       when is_binary(source_root) and is_binary(rel_path),
       do: ResourceStore.read_only_generated_module?(source_root, rel_path)

  defp read_only_tab?(_), do: false

  defp editor_state_value(state, key) when is_map(state) do
    Map.get(state, key, 0) || 0
  end

  defp editor_state_value(_state, _key), do: 0

  @spec protected_editor_source_file?(String.t()) :: boolean()
  defp protected_editor_source_file?(rel_path) when is_binary(rel_path),
    do: rel_path in @protected_editor_rel_paths

  defp protected_editor_source_file?(_), do: false

  defp editor_read_only?(%{read_only: true}), do: true

  defp editor_read_only?(%{source_root: source_root, rel_path: rel_path})
       when is_binary(source_root) and is_binary(rel_path),
       do: ResourceStore.read_only_generated_module?(source_root, rel_path)

  defp editor_read_only?(_), do: false

  @spec editor_pane_style(boolean(), integer()) :: String.t()
  defp editor_pane_style(docs_open?, px) when is_integer(px) do
    editor_pane_grid_style(docs_open?, px)
  end

  @spec editor_pane_grid_style(boolean(), integer()) :: String.t()
  defp editor_pane_grid_style(docs_open?, px) when is_integer(px) do
    if docs_open? do
      "grid-template-columns: 16rem minmax(0, 1fr) 6px #{px}px; min-height: 0;"
    else
      "grid-template-columns: 16rem minmax(0, 1fr); min-height: 0;"
    end
  end

  @spec editor_files_tree([map()]) :: [map()]
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
  @spec flatten_protocol_companion_dir([tree_node()]) :: [tree_node()]
  defp flatten_protocol_companion_dir(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, fn
      %{type: :dir, name: "Companion", children: kids} when is_list(kids) -> kids
      other -> [other]
    end)
  end

  @spec editor_source_display_path(String.t()) :: String.t()
  defp editor_source_display_path("src/" <> rest), do: rest
  defp editor_source_display_path(rel) when is_binary(rel), do: rel

  @spec settings_path_with_return_to(String.t()) :: String.t()
  defp settings_path_with_return_to(return_to) when is_binary(return_to) do
    "/settings?return_to=#{URI.encode_www_form(return_to)}"
  end

  @spec tokenizer_mode_label(atom()) :: String.t()
  defp tokenizer_mode_label(:compiler), do: "elmc"
  defp tokenizer_mode_label(:fast), do: "fast"
  defp tokenizer_mode_label(:plain), do: "plain"
  defp tokenizer_mode_label(_), do: "fast"

  @spec diagnostic_position_label(diagnostic()) :: String.t() | nil
  defp diagnostic_position_label(diag) do
    line = diagnostic_line(diag)
    column = diagnostic_column(diag)
    end_line = diagnostic_int(diag, :end_line)
    end_column = diagnostic_int(diag, :end_column)

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

  @spec diagnostic_file_position_label(diagnostic()) :: String.t()
  defp diagnostic_file_position_label(diag) when is_map(diag) do
    file = diag[:file] || diag["file"]

    case diagnostic_position_label(diag) do
      nil when is_binary(file) and file != "" -> file
      nil -> nil
      position when is_binary(file) and file != "" -> "#{file}:#{position}"
      position -> position
    end
  end

  @spec editor_check_visible?(
          atom(),
          String.t() | nil,
          String.t() | nil,
          [diagnostic()] | nil,
          tab() | nil
        ) :: boolean()
  defp editor_check_visible?(:error, source_root, rel_path, diagnostics, active)
       when is_map(active) do
    active_source_root = active[:source_root] || active["source_root"]
    active_rel_path = active[:rel_path] || active["rel_path"]

    source_root == active_source_root and
      (rel_path == active_rel_path or
         Enum.any?(List.wrap(diagnostics), &diagnostic_file_matches_active?(&1, active)))
  end

  defp editor_check_visible?(_status, _source_root, _rel_path, _diagnostics, _active), do: false

  @spec editor_check_running_for_active?(atom(), tab() | nil, String.t() | nil, String.t() | nil) ::
          boolean()
  defp editor_check_running_for_active?(:running, source_root, rel_path, active)
       when is_map(active) do
    active_source_root = active[:source_root] || active["source_root"]
    active_rel_path = active[:rel_path] || active["rel_path"]

    source_root == active_source_root and rel_path == active_rel_path
  end

  defp editor_check_running_for_active?(_status, _source_root, _rel_path, _active), do: false

  @spec diagnostic_editor_jumpable?(diagnostic(), tab() | nil) :: boolean()
  defp diagnostic_editor_jumpable?(diag, active) do
    is_integer(diagnostic_line(diag)) and diagnostic_file_matches_active?(diag, active)
  end

  @spec diagnostic_file_matches_active?(diagnostic(), tab() | nil) :: boolean()
  defp diagnostic_file_matches_active?(diag, active) when is_map(diag) and is_map(active) do
    file = diag[:file] || diag["file"]
    rel_path = active[:rel_path] || active["rel_path"]
    source_root = active[:source_root] || active["source_root"]

    cond do
      not is_binary(file) or file == "" ->
        true

      file == rel_path ->
        true

      is_binary(source_root) and file == Path.join(source_root, rel_path || "") ->
        true

      true ->
        false
    end
  end

  defp diagnostic_file_matches_active?(_diag, _active), do: false

  @spec diagnostic_line(diagnostic()) :: integer() | nil
  defp diagnostic_line(diag), do: diagnostic_int(diag, :line)

  @spec diagnostic_column(diagnostic()) :: integer() | nil
  defp diagnostic_column(diag), do: diagnostic_int(diag, :column)

  @spec phx_value_int(integer() | nil) :: String.t()
  defp phx_value_int(value) when is_integer(value), do: Integer.to_string(value)
  defp phx_value_int(_value), do: "0"

  @spec diagnostic_int(diagnostic(), atom()) :: integer() | nil
  defp diagnostic_int(diag, key) when is_map(diag) do
    case diag[key] || diag[Atom.to_string(key)] do
      value when is_integer(value) and value > 0 -> value
      value when is_binary(value) -> parse_positive_int(value)
      _ -> nil
    end
  end

  defp diagnostic_int(_diag, _key), do: nil

  @spec parse_positive_int(String.t()) :: integer() | nil
  defp parse_positive_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> nil
    end
  end

  @spec editor_check_engine_label(String.t()) :: String.t()
  defp editor_check_engine_label("phone"), do: "Elm compiler"
  defp editor_check_engine_label(_source_root), do: "elmc check"
end
