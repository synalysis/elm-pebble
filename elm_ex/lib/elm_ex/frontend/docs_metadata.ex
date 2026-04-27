defmodule ElmEx.Frontend.DocsMetadata do
  @moduledoc """
  Extracts Elm package documentation metadata from source files.

  This module complements `ElmEx.Frontend.GeneratedParser`: the generated parser
  owns module/exposing/declaration structure, while this helper preserves the
  doc comments and `@docs` ordering that package documentation needs.
  """

  alias ElmEx.Frontend.GeneratedParser

  @type declaration :: %{
          required(:kind) => :alias | :union | :value,
          required(:name) => String.t(),
          required(:comment) => String.t(),
          optional(:args) => [String.t()],
          optional(:type) => String.t(),
          optional(:cases) => [[String.t() | [String.t()]]],
          optional(:line) => pos_integer()
        }

  @type t :: %{
          required(:name) => String.t(),
          required(:path) => String.t(),
          required(:comment) => String.t(),
          required(:docs) => [String.t()],
          required(:module_exposing) => term(),
          required(:declarations) => %{optional(String.t()) => declaration()}
        }

  @spec parse_file(String.t()) :: {:ok, t()} | {:error, map()}
  def parse_file(path) when is_binary(path) do
    with {:ok, source} <- File.read(path),
         :ok <- tokenize_source(source),
         {:ok, mod} <- GeneratedParser.parse_file(path) do
      {:ok, source_to_metadata(path, source, mod)}
    else
      {:error, %{} = reason} -> {:error, reason}
      {:error, reason} -> {:error, %{kind: :docs_metadata_error, reason: reason, path: path}}
    end
  end

  @spec source_to_metadata(String.t(), String.t(), ElmEx.Frontend.Module.t()) :: t()
  def source_to_metadata(path, source, mod) when is_binary(source) do
    state =
      source
      |> String.split("\n", trim: false)
      |> parse_lines(%{
        i: 0,
        pending_doc: nil,
        module_comment: nil,
        seen_declaration: false,
        declarations: %{}
      })

    module_comment = state.module_comment || ""

    %{
      name: mod.name,
      path: path,
      comment: module_comment,
      docs: docs_order(module_comment),
      module_exposing: mod.module_exposing || parse_module_exposing(source),
      declarations: state.declarations
    }
  end

  @spec parse_module_exposing(String.t()) :: term()
  defp parse_module_exposing(source) do
    with {:ok, after_open} <- exposing_chars(source),
         {:ok, inner} <- take_balanced_exposing(after_open, 1, []) do
      inner
      |> Enum.reverse()
      |> to_string()
      |> parse_exposing_text()
    else
      _ -> nil
    end
  end

  @spec exposing_chars(String.t()) :: {:ok, [char()]} | :error
  defp exposing_chars(source) do
    source
    |> String.to_charlist()
    |> drop_until_exposing()
  end

  @spec drop_until_exposing([char()]) :: {:ok, [char()]} | :error
  defp drop_until_exposing([]), do: :error

  defp drop_until_exposing(chars) do
    text = to_string(chars)

    case Regex.run(~r/\A.*?\bexposing\s*\(/s, text) do
      [prefix] ->
        {:ok, String.to_charlist(String.replace_prefix(text, prefix, ""))}

      _ ->
        :error
    end
  end

  @spec take_balanced_exposing([char()], non_neg_integer(), [char()]) ::
          {:ok, [char()]} | :error
  defp take_balanced_exposing([], _depth, _acc), do: :error

  defp take_balanced_exposing([?( | rest], depth, acc),
    do: take_balanced_exposing(rest, depth + 1, [?( | acc])

  defp take_balanced_exposing([?) | _rest], 1, acc), do: {:ok, acc}

  defp take_balanced_exposing([?) | rest], depth, acc),
    do: take_balanced_exposing(rest, depth - 1, [?) | acc])

  defp take_balanced_exposing([char | rest], depth, acc),
    do: take_balanced_exposing(rest, depth, [char | acc])

  @spec parse_exposing_text(String.t()) :: term()
  defp parse_exposing_text(text) do
    if String.trim(text) == ".." do
      ".."
    else
      text
      |> split_top_level_commas()
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
    end
  end

  @spec split_top_level_commas(String.t()) :: [String.t()]
  defp split_top_level_commas(text) do
    {parts, current, _depth} =
      text
      |> String.to_charlist()
      |> Enum.reduce({[], [], 0}, fn
        ?,, {parts, current, 0} ->
          {[current |> Enum.reverse() |> to_string() | parts], [], 0}

        ?(, {parts, current, depth} ->
          {parts, [?( | current], depth + 1}

        ?), {parts, current, depth} ->
          {parts, [?) | current], max(depth - 1, 0)}

        char, {parts, current, depth} ->
          {parts, [char | current], depth}
      end)

    Enum.reverse([current |> Enum.reverse() |> to_string() | parts])
  end

  @spec tokenize_source(String.t()) :: :ok | {:error, map()}
  defp tokenize_source(source) do
    case :elm_ex_elm_lexer.string(String.to_charlist(source)) do
      {:ok, _tokens, _line} ->
        :ok

      {:error, reason, line} ->
        {:error, %{kind: :tokenize_error, reason: reason, line: line}}
    end
  end

  @spec parse_lines([String.t()], map()) :: map()
  defp parse_lines(lines, state) do
    if state.i >= length(lines) do
      state
    else
      line = Enum.at(lines, state.i) || ""
      trimmed = String.trim(line)

      cond do
        String.starts_with?(trimmed, "{-|") ->
          {doc, next_i} = read_doc_block(lines, state.i)

          next_state =
            if is_nil(state.module_comment) and not state.seen_declaration and
                 String.contains?(doc, "@docs") do
              %{state | module_comment: doc, pending_doc: nil, i: next_i}
            else
              %{state | pending_doc: doc, i: next_i}
            end

          parse_lines(lines, next_state)

        maybe_assign_module_doc?(trimmed, state) ->
          parse_lines(lines, %{
            state
            | module_comment: state.pending_doc,
              pending_doc: nil,
              i: state.i + 1
          })

        value_signature_line?(trimmed) ->
          state
          |> maybe_promote_pending_to_module_doc()
          |> add_value(lines)
          |> then(&parse_lines(lines, &1))

        type_alias_line?(trimmed) ->
          state
          |> maybe_promote_pending_to_module_doc()
          |> add_type_alias(lines)
          |> then(&parse_lines(lines, &1))

        union_type_line?(trimmed) ->
          state
          |> maybe_promote_pending_to_module_doc()
          |> add_union(lines)
          |> then(&parse_lines(lines, &1))

        true ->
          parse_lines(lines, %{state | i: state.i + 1})
      end
    end
  end

  @spec maybe_assign_module_doc?(String.t(), map()) :: boolean()
  defp maybe_assign_module_doc?(trimmed, state) do
    not state.seen_declaration and is_binary(state.pending_doc) and is_nil(state.module_comment) and
      (String.starts_with?(trimmed, "import ") or declaration_line?(trimmed))
  end

  @spec maybe_promote_pending_to_module_doc(map()) :: map()
  defp maybe_promote_pending_to_module_doc(state) do
    if is_nil(state.module_comment) and is_binary(state.pending_doc) and
         String.contains?(state.pending_doc, "@docs") do
      %{state | module_comment: state.pending_doc, pending_doc: nil}
    else
      state
    end
  end

  @spec read_doc_block([String.t()], non_neg_integer()) :: {String.t(), non_neg_integer()}
  defp read_doc_block(lines, start_i) do
    do_read_doc_block(lines, start_i, [])
  end

  @spec do_read_doc_block([String.t()], non_neg_integer(), [String.t()]) ::
          {String.t(), non_neg_integer()}
  defp do_read_doc_block(lines, i, acc) do
    line = Enum.at(lines, i) || ""
    acc = [line | acc]

    cond do
      String.contains?(line, "-}") ->
        doc =
          acc
          |> Enum.reverse()
          |> Enum.join("\n")
          |> clean_doc_block()

        {doc, i + 1}

      i + 1 >= length(lines) ->
        {clean_doc_block(Enum.reverse(acc) |> Enum.join("\n")), i + 1}

      true ->
        do_read_doc_block(lines, i + 1, acc)
    end
  end

  @spec clean_doc_block(String.t()) :: String.t()
  defp clean_doc_block(text) do
    text
    |> String.replace(~r/\A\s*\{\-\|\s?/, "")
    |> String.replace(~r/\s*\-\}\s*\z/, "")
    |> dedent()
    |> String.trim()
  end

  @spec dedent(String.t()) :: String.t()
  defp dedent(text) do
    lines = String.split(text, "\n", trim: false)

    min_indent =
      lines
      |> Enum.reject(&(String.trim(&1) == ""))
      |> Enum.map(fn line ->
        case Regex.run(~r/^\s*/, line) do
          [indent] -> String.length(indent)
          _ -> 0
        end
      end)
      |> case do
        [] -> 0
        values -> Enum.min(values)
      end

    lines
    |> Enum.map(fn line ->
      if String.trim(line) == "" do
        ""
      else
        String.slice(line, min_indent, String.length(line) - min_indent)
      end
    end)
    |> Enum.join("\n")
  end

  @spec docs_order(String.t()) :: [String.t()]
  defp docs_order(module_comment) do
    module_comment
    |> String.split("\n", trim: false)
    |> Enum.flat_map(fn line ->
      trimmed = String.trim(line)

      if String.starts_with?(trimmed, "@docs") do
        trimmed
        |> String.replace_prefix("@docs", "")
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
      else
        []
      end
    end)
  end

  @spec declaration_line?(String.t()) :: boolean()
  defp declaration_line?(trimmed) do
    value_signature_line?(trimmed) or type_alias_line?(trimmed) or union_type_line?(trimmed)
  end

  @spec value_signature_line?(String.t()) :: boolean()
  defp value_signature_line?(trimmed), do: Regex.match?(~r/^[a-z][A-Za-z0-9_']*\s*:/, trimmed)

  @spec type_alias_line?(String.t()) :: boolean()
  defp type_alias_line?(trimmed), do: String.starts_with?(trimmed, "type alias ")

  @spec union_type_line?(String.t()) :: boolean()
  defp union_type_line?(trimmed),
    do: String.starts_with?(trimmed, "type ") and not type_alias_line?(trimmed)

  @spec add_value(map(), [String.t()]) :: map()
  defp add_value(state, lines) do
    line = Enum.at(lines, state.i) || ""
    trimmed = String.trim(line)
    [_, name, first_type] = Regex.run(~r/^([a-z][A-Za-z0-9_']*)\s*:\s*(.*)$/, trimmed)
    {type, next_i} = read_value_type(lines, state.i + 1, name, [first_type])
    {comment, state} = pop_pending_doc(state)

    put_declaration(state, name, %{
      kind: :value,
      name: name,
      type: String.trim(type),
      comment: comment,
      line: state.i + 1
    })
    |> Map.merge(%{i: next_i, seen_declaration: true})
  end

  @spec read_value_type([String.t()], non_neg_integer(), String.t(), [String.t()]) ::
          {String.t(), non_neg_integer()}
  defp read_value_type(lines, i, name, acc) do
    if i >= length(lines) do
      {Enum.join(acc, "\n"), i}
    else
      line = Enum.at(lines, i) || ""
      trimmed = String.trim(line)

      cond do
        trimmed == "" ->
          {Enum.join(acc, "\n"), i}

        Regex.match?(~r/^#{Regex.escape(name)}\b.*=/, trimmed) ->
          {Enum.join(acc, "\n"), i}

        String.starts_with?(line, "    ") or String.starts_with?(line, "\t") ->
          read_value_type(lines, i + 1, name, acc ++ [trimmed])

        true ->
          {Enum.join(acc, "\n"), i}
      end
    end
  end

  @spec add_type_alias(map(), [String.t()]) :: map()
  defp add_type_alias(state, lines) do
    line = Enum.at(lines, state.i) || ""
    trimmed = String.trim(line)

    [_, name, arg_text, first_body] =
      Regex.run(~r/^type alias\s+([A-Z][A-Za-z0-9_']*)(.*?)=\s*(.*)$/, trimmed)

    args = parse_args(arg_text)
    {body, next_i} = read_alias_body(lines, state.i + 1, first_body, name)
    {comment, state} = pop_pending_doc(state)

    put_declaration(state, name, %{
      kind: :alias,
      name: name,
      args: args,
      type: String.trim(body),
      comment: comment,
      line: state.i + 1
    })
    |> Map.merge(%{i: next_i, seen_declaration: true})
  end

  @spec read_alias_body([String.t()], non_neg_integer(), String.t(), String.t()) ::
          {String.t(), non_neg_integer()}
  defp read_alias_body(lines, i, first_body, name) do
    acc = if first_body == "", do: [], else: [first_body]
    do_read_alias_body(lines, i, name, acc)
  end

  @spec do_read_alias_body([String.t()], non_neg_integer(), String.t(), [String.t()]) ::
          {String.t(), non_neg_integer()}
  defp do_read_alias_body(lines, i, name, acc) do
    if i >= length(lines) do
      {Enum.join(acc, "\n"), i}
    else
      line = Enum.at(lines, i) || ""
      trimmed = String.trim(line)

      cond do
        trimmed == "" ->
          {Enum.join(acc, "\n"), i}

        declaration_line?(trimmed) ->
          {Enum.join(acc, "\n"), i}

        Regex.match?(~r/^#{Regex.escape(name)}\b/, trimmed) ->
          {Enum.join(acc, "\n"), i}

        String.starts_with?(line, "    ") or String.starts_with?(line, "\t") ->
          do_read_alias_body(lines, i + 1, name, acc ++ [trimmed])

        true ->
          {Enum.join(acc, "\n"), i}
      end
    end
  end

  @spec add_union(map(), [String.t()]) :: map()
  defp add_union(state, lines) do
    line = Enum.at(lines, state.i) || ""
    trimmed = String.trim(line)

    {name, arg_text, first_ctor} =
      case Regex.run(~r/^type\s+([A-Z][A-Za-z0-9_']*)(.*?)=\s*(.*)$/, trimmed) do
        [_, n, a, ctor] ->
          {n, a, ctor}

        _ ->
          case Regex.run(~r/^type\s+([A-Z][A-Za-z0-9_']*)(.*?)$/, trimmed) do
            [_, n, a] -> {n, a, nil}
            _ -> {"", "", nil}
          end
      end

    args = parse_args(arg_text)
    {cases, next_i} = read_union_cases(lines, state.i + 1, first_ctor)
    {comment, state} = pop_pending_doc(state)

    put_declaration(state, name, %{
      kind: :union,
      name: name,
      args: args,
      cases: cases,
      comment: comment,
      line: state.i + 1
    })
    |> Map.merge(%{i: next_i, seen_declaration: true})
  end

  @spec read_union_cases([String.t()], non_neg_integer(), String.t() | nil) ::
          {[[String.t() | [String.t()]]], non_neg_integer()}
  defp read_union_cases(lines, i, first_ctor) do
    acc =
      case normalize_ctor(first_ctor) do
        nil -> []
        ctor -> [ctor]
      end

    do_read_union_cases(lines, i, acc)
  end

  @spec do_read_union_cases([String.t()], non_neg_integer(), [[String.t() | [String.t()]]]) ::
          {[[String.t() | [String.t()]]], non_neg_integer()}
  defp do_read_union_cases(lines, i, acc) do
    if i >= length(lines) do
      {Enum.reverse(acc), i}
    else
      line = Enum.at(lines, i) || ""
      trimmed = String.trim(line)

      cond do
        trimmed == "" and acc != [] ->
          {Enum.reverse(acc), i}

        String.starts_with?(trimmed, "|") ->
          ctor = normalize_ctor(String.trim_leading(trimmed, "|") |> String.trim())
          next_acc = if ctor, do: [ctor | acc], else: acc
          do_read_union_cases(lines, i + 1, next_acc)

        String.starts_with?(trimmed, "=") ->
          ctor = normalize_ctor(String.trim_leading(trimmed, "=") |> String.trim())
          next_acc = if ctor, do: [ctor | acc], else: acc
          do_read_union_cases(lines, i + 1, next_acc)

        true ->
          {Enum.reverse(acc), i}
      end
    end
  end

  @spec normalize_ctor(String.t() | nil) :: [String.t() | [String.t()]] | nil
  defp normalize_ctor(nil), do: nil

  defp normalize_ctor(text) do
    tokens = text |> String.trim() |> String.split(~r/\s+/, trim: true)

    case tokens do
      [] -> nil
      [name | args] -> [name, args]
    end
  end

  @spec parse_args(String.t()) :: [String.t()]
  defp parse_args(text) do
    text
    |> String.trim()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reject(&(&1 == ""))
  end

  @spec pop_pending_doc(map()) :: {String.t(), map()}
  defp pop_pending_doc(state) do
    case state.pending_doc do
      doc when is_binary(doc) -> {doc, %{state | pending_doc: nil}}
      _ -> {"", state}
    end
  end

  @spec put_declaration(map(), String.t(), declaration()) :: map()
  defp put_declaration(state, name, declaration) do
    %{state | declarations: Map.put(state.declarations, name, declaration)}
  end
end
