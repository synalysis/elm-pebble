defmodule IdeWeb.WorkspaceLive.EditorSupport do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2, assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [connected?: 1, push_event: 3, start_async: 3]

  alias Ide.ElmFormat
  alias Ide.Formatter
  alias Ide.Packages
  alias Ide.Projects
  alias Ide.Resources.ResourceStore
  alias Ide.Tokenizer
  alias IdeWeb.WorkspaceLive.EditorDependencies
  alias IdeWeb.WorkspaceLive.PackagesFlow

  @max_editor_highlight_tokens 25_000
  @max_editor_fold_ranges 2_000
  @max_editor_lint_diagnostics 1_000
  @min_bracket_fold_span_lines 10
  @protected_editor_rel_paths [
    "src/Main.elm",
    "src/CompanionApp.elm",
    "src/Companion/Types.elm",
    "src/Pebble/Ui/Resources.elm"
  ]

  @spec active_tab(term()) :: term()
  def active_tab(socket), do: active_tab(socket.assigns.tabs, socket.assigns.active_tab_id)

  def active_tab(tabs, active_tab_id), do: Enum.find(tabs, &(&1.id == active_tab_id))

  @spec read_only_tab?(term()) :: term()
  def read_only_tab?(%{read_only: true}), do: true
  def read_only_tab?(_), do: false

  @spec ensure_can_modify_editor_file(term()) :: term()
  def ensure_can_modify_editor_file(%{rel_path: rel_path} = tab) do
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
  def protected_editor_source_file?(rel_path) when is_binary(rel_path),
    do: rel_path in @protected_editor_rel_paths

  def protected_editor_source_file?(_), do: false

  @spec doc_catalog_source_root(term()) :: term()
  def doc_catalog_source_root(socket) do
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
  def preferred_packages_target_root(socket, project) do
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

  @spec update_tab(term(), term()) :: term()
  def update_tab(socket, updater) do
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
  def update_active_tab(socket, updater) do
    if socket.assigns.active_tab_id do
      update_tab(socket, updater)
    else
      socket
    end
  end

  def update_editor_state_tab(socket, tab_id, updater) when is_binary(tab_id) do
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

  def update_editor_state_tab(socket, _tab_id, updater), do: update_active_tab(socket, updater)

  @spec refresh_tree(term()) :: term()
  def refresh_tree(socket) do
    socket
    |> assign(:tree, Projects.list_source_tree(socket.assigns.project))
    |> refresh_editor_dependencies()
  end

  @spec refresh_editor_dependencies(term()) :: term()
  def refresh_editor_dependencies(socket) do
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
  def editor_source_display_path("src/" <> rest), do: rest
  def editor_source_display_path(rel) when is_binary(rel), do: rel

  @spec editor_file_tree_label(term(), term()) :: term()
  def editor_file_tree_label("protocol", rel_path) when is_binary(rel_path) do
    rel_path
    |> editor_source_display_path()
    |> case do
      "Companion/" <> rest -> rest
      other -> other
    end
  end

  def editor_file_tree_label(_source_root, rel_path) when is_binary(rel_path) do
    editor_source_display_path(rel_path)
  end

  @spec normalize_editor_src_rel_path(term()) :: term()
  def normalize_editor_src_rel_path(path) when is_binary(path) do
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
  def settings_path_with_return_to(return_to) when is_binary(return_to) do
    "/settings?return_to=#{URI.encode_www_form(return_to)}"
  end

  @spec module_name_from_rel_path(term()) :: term()
  def module_name_from_rel_path("src/" <> rel_path) when is_binary(rel_path) do
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

  def module_name_from_rel_path(_), do: {:error, :invalid_rel_path}

  @spec validate_new_elm_module_name(term()) :: term()
  def validate_new_elm_module_name(module_name) when is_binary(module_name) do
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
  def elm_module_segment?(segment) when is_binary(segment) do
    String.match?(segment, ~r/^[A-Z][A-Za-z0-9_]*$/)
  end

  def elm_module_segment?(_), do: false

  @spec new_elm_module_template(term()) :: term()
  def new_elm_module_template(module_name) when is_binary(module_name) do
    "module #{module_name} exposing (..)\n\n"
  end

  @spec maybe_initialize_forms(term(), term()) :: term()
  def maybe_initialize_forms(socket, project) do
    source_root = List.first(project.source_roots) || "watch"

    socket
    |> assign(
      :new_file_form,
      to_form(%{"source_root" => source_root, "rel_path" => ""}, as: :new_file)
    )
    |> assign(:rename_form, to_form(%{"new_rel_path" => ""}, as: :rename))
  end

  def maybe_open_editor_default_file(socket, project, previous_pane) do
    if socket.assigns.live_action == :editor and
         (previous_pane != :editor or is_nil(active_tab(socket))) do
      open_editor_default_file(socket, project)
    else
      socket
    end
  end

  def open_editor_default_file(socket, project) do
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

  def editor_entry_candidates do
    [{"watch", "src/Main.elm"}, {"watch", "Main.elm"}]
  end

  def default_editor_state do
    %{
      cursor_offset: 0,
      scroll_top: 0,
      scroll_left: 0,
      active_diagnostic_index: 0
    }
  end

  @spec tab_id(term(), term()) :: term()
  def tab_id(source_root, rel_path), do: "#{source_root}:#{rel_path}"

  @spec tree_dir_key(term(), term()) :: term()
  def tree_dir_key(source_root, rel_path), do: "#{source_root}:#{rel_path}"

  @spec maybe_put_kw(term(), term(), term()) :: term()
  def maybe_put_kw(opts, _key, nil), do: opts
  def maybe_put_kw(opts, _key, ""), do: opts
  def maybe_put_kw(opts, key, value), do: Keyword.put(opts, key, value)

  @spec apply_text_patch(term(), term()) :: term()
  def apply_text_patch(content, %{replace_from: from, replace_to: to, inserted_text: inserted})
      when is_binary(content) and is_integer(from) and is_integer(to) and is_binary(inserted) do
    String.slice(content, 0, from) <>
      inserted <> String.slice(content, to, String.length(content) - to)
  end

  @spec identity_edit_patch(term(), term(), term()) :: term()
  def identity_edit_patch(content, start_offset, end_offset) when is_binary(content) do
    %{
      replace_from: start_offset,
      replace_to: end_offset,
      inserted_text: String.slice(content, start_offset, end_offset - start_offset),
      cursor_start: start_offset,
      cursor_end: end_offset
    }
  end

  @spec semantic_edit_ops_enabled?() :: term()
  def semantic_edit_ops_enabled? do
    Application.get_env(:ide, Ide.Formatter, [])
    |> Keyword.get(:semantic_edit_ops, true)
  end

  @spec render_format_output(term()) :: term()
  def render_format_output(result) do
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
  def format_parser_reuse(%{details: %{parser_payload_reused?: value}}), do: value
  def format_parser_reuse(_), do: "unknown"

  @spec formatted_cursor_offset(term(), String.t()) :: non_neg_integer()
  def formatted_cursor_offset(socket, formatted_source) do
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
  def editor_cursor_offset(state) when is_map(state) do
    case Map.get(state, :cursor_offset, Map.get(state, "cursor_offset", 0)) do
      value when is_integer(value) and value >= 0 -> value
      _ -> 0
    end
  end

  def editor_cursor_offset(_), do: 0

  @spec render_format_error(term()) :: term()
  def render_format_error(reason) when is_map(reason) do
    format_diagnostic_line(reason)
  end

  def render_format_error(reason), do: inspect(reason)

  @spec format_diagnostic_line(term()) :: term()
  def format_diagnostic_line(diag) do
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
  def diagnostic_structured_lines(diag) when is_map(diag) do
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

  def diagnostic_structured_lines(_), do: []

  @spec maybe_diag_detail(term(), term(), term()) :: term()
  def maybe_diag_detail(lines, _label, nil), do: lines

  def maybe_diag_detail(lines, label, value) do
    rendered =
      case value do
        atom when is_atom(atom) -> Atom.to_string(atom)
        other -> to_string(other)
      end

    lines ++ ["#{label}=#{rendered}"]
  end

  @spec tokenize_content(term(), term(), term()) :: term()
  def tokenize_content(content, rel_path, opts) do
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
  def assign_tokenization(socket, content, rel_path, opts \\ [])

  def assign_tokenization(socket, nil, _rel_path, _opts) do
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

  def assign_tokenization(socket, content, rel_path, opts) do
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
  def sync_parser_panel_from_tokenizer(socket, rel_path, :compiler) when is_binary(rel_path) do
    diagnostics =
      socket.assigns.token_diagnostics
      |> Enum.map(fn diag ->
        diag
        |> Map.put(:file, rel_path)
        |> Map.put_new(:source, "tokenizer")
      end)

    assign(socket, :diagnostics, diagnostics)
  end

  def sync_parser_panel_from_tokenizer(socket, _rel_path, _mode), do: socket

  @spec push_editor_token_highlights(term(), term(), term()) :: term()
  def push_editor_token_highlights(socket, tokens, tokenizer_mode) do
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
  def push_editor_fold_ranges(socket, content, tokens, parser_payload)
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

  def push_editor_fold_ranges(socket, _content, _tokens, _parser_payload), do: socket

  @spec push_editor_lint_diagnostics(term(), term()) :: term()
  def push_editor_lint_diagnostics(socket, diagnostics) when is_list(diagnostics) do
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
  def diagnostic_value(diag, key) when is_map(diag) and is_atom(key) do
    Map.get(diag, key) || Map.get(diag, Atom.to_string(key))
  end

  def diagnostic_value(_diag, _key), do: nil

  @spec parser_header_fold_ranges(term()) :: term()
  def parser_header_fold_ranges(%{metadata: metadata}) when is_map(metadata) do
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

  def parser_header_fold_ranges(_), do: []

  @spec top_level_declaration_fold_ranges(term()) :: term()
  def top_level_declaration_fold_ranges(content) when is_binary(content) do
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
  def type_declaration_fold_ranges(content) when is_binary(content) do
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
  def type_declaration_start_line?(line) when is_binary(line) do
    trimmed = String.trim_leading(line)
    indent = String.length(line) - String.length(trimmed)

    indent == 0 and
      (Regex.match?(~r/^type\s+alias\s+[A-Z][A-Za-z0-9_']*/, trimmed) or
         Regex.match?(~r/^type\s+[A-Z][A-Za-z0-9_']*/, trimmed))
  end

  @spec top_level_fold_start_line?(term()) :: term()
  def top_level_fold_start_line?(line) when is_binary(line) do
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
  def last_non_blank_line(lines, from_line) when is_list(lines) and is_integer(from_line) do
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
  def token_comment_fold_ranges(tokens) do
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
  def token_delimiter_fold_ranges(tokens) do
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
  def delimiter_match?("(", ")"), do: true
  def delimiter_match?("[", "]"), do: true
  def delimiter_match?("{", "}"), do: true
  def delimiter_match?(_, _), do: false

  @spec elm_source_file?(term()) :: term()
  def elm_source_file?(rel_path) when is_binary(rel_path),
    do: String.ends_with?(rel_path, ".elm")

  def elm_source_file?(_), do: false

  @spec annotate_tokens_with_diagnostics(term(), term()) :: term()
  def annotate_tokens_with_diagnostics(tokens, diagnostics) do
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
  def format_diagnostic_message(diag) do
    line = diag[:line] || "?"
    column = diag[:column] || "?"
    "[#{diag.severity}] #{diag.source} @ #{line}:#{column} - #{diag.message}"
  end

  @spec parse_positive_int(term()) :: term()
  def parse_positive_int(nil), do: nil

  def parse_positive_int(value) when is_integer(value) and value > 0, do: value

  def parse_positive_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> nil
    end
  end

  def parse_positive_int(_), do: nil

  @spec parse_non_negative_int(term()) :: term()
  def parse_non_negative_int(nil), do: nil
  def parse_non_negative_int(value) when is_integer(value) and value >= 0, do: value

  def parse_non_negative_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int >= 0 -> int
      _ -> nil
    end
  end

  def parse_non_negative_int(_), do: nil

  def parse_non_negative_number(nil), do: nil
  def parse_non_negative_number(value) when is_integer(value) and value >= 0, do: value
  def parse_non_negative_number(value) when is_float(value) and value >= 0, do: value

  def parse_non_negative_number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} when number >= 0 -> number
      _ -> nil
    end
  end

  def parse_non_negative_number(_), do: nil

  @spec completion_replace_range(term(), term()) :: term()
  def completion_replace_range(content, cursor) when is_binary(content) and is_integer(cursor) do
    safe_cursor = min(max(cursor, 0), String.length(content))
    prefix = String.slice(content, 0, safe_cursor)
    match = Regex.run(~r/([A-Za-z_][A-Za-z0-9_']*)$/, prefix)
    token = if is_list(match), do: List.last(match), else: ""
    from = safe_cursor - String.length(token)
    {from, safe_cursor, token}
  end

  @spec maybe_put_state(term(), term(), term()) :: term()
  def maybe_put_state(state, _key, nil), do: state
  def maybe_put_state(state, key, value), do: Map.put(state, key, value)

  @spec sync_active_diagnostic_index_to_tab(term()) :: term()
  def sync_active_diagnostic_index_to_tab(socket) do
    idx = socket.assigns[:active_diagnostic_index]

    update_active_tab(socket, fn tab ->
      state = tab.editor_state || %{}
      %{tab | editor_state: Map.put(state, :active_diagnostic_index, idx)}
    end)
  end

  @spec restore_editor_state(term(), term()) :: term()
  def restore_editor_state(socket, state) when is_map(state) do
    cursor_offset = state[:cursor_offset] || 0
    scroll_top = state[:scroll_top] || 0
    scroll_left = state[:scroll_left] || 0

    push_event(socket, "token-editor-restore-state", %{
      cursor_offset: cursor_offset,
      scroll_top: scroll_top,
      scroll_left: scroll_left
    })
  end

  def restore_editor_state(socket, _), do: socket

  @spec focus_diagnostic(term(), term()) :: term()
  def focus_diagnostic(socket, direction) do
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
  def normalize_active_diagnostic_index(nil, diagnostics),
    do: if(diagnostics == [], do: nil, else: 0)

  def normalize_active_diagnostic_index(index, diagnostics)
      when is_integer(index) and index >= 0 do
    if index < length(diagnostics), do: index, else: nil
  end

  def normalize_active_diagnostic_index(_index, diagnostics),
    do: if(diagnostics == [], do: nil, else: 0)

  @spec diagnostic_hits_token?(term(), term()) :: term()
  def diagnostic_hits_token?(diag, token) do
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
  def ranges_overlap?(a_start, a_end, b_start, b_end) do
    max(a_start, b_start) <= min(a_end, b_end)
  end

  @spec prepare_content_for_save(term(), term(), term(), term(), term(), term()) :: term()
  def prepare_content_for_save(
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
  def format_source(project, tab, :elm_format, _parser_payload, _tokens) do
    ElmFormat.format(tab.content, cwd: source_root_path(project, tab.source_root))
  end

  def format_source(_project, tab, _formatter_backend, parser_payload, tokens) do
    Formatter.format(tab.content,
      rel_path: tab.rel_path,
      parser_payload: parser_payload,
      tokens: tokens
    )
  end

  @spec source_root_path(term(), term()) :: String.t()
  def source_root_path(project, source_root) do
    project
    |> Projects.project_workspace_path()
    |> Path.join(source_root)
  end

  @spec token_diagnostics_by_line(term()) :: term()
  def token_diagnostics_by_line(diagnostics) do
    diagnostics
    |> Enum.filter(&is_integer(&1[:line]))
    |> Enum.group_by(& &1.line)
  end

  @spec inline_diagnostics(term(), term()) :: term()
  def inline_diagnostics(diagnostics, lines) do
    diagnostics
    |> Enum.filter(&is_integer(&1[:line]))
    |> Enum.map(fn diag ->
      line = diag.line
      snippet = if line >= 1, do: Enum.at(lines, line - 1), else: nil
      Map.put(diag, :snippet, snippet)
    end)
  end
end
