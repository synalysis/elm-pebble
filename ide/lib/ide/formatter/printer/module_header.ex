defmodule Ide.Formatter.Printer.ModuleHeader do
  @moduledoc false
  alias Ide.Formatter.Doc

  @spec normalize(String.t(), map()) :: String.t()
  def normalize(source, metadata) when is_binary(source) and is_map(metadata) do
    module_name = metadata[:module]
    module_line = get_in(metadata, [:header_lines, :module])
    import_entries = metadata[:import_entries] || []

    import_entries_by_line =
      import_entries
      |> Enum.filter(&is_integer(&1["line"]))
      |> Map.new(&{&1["line"], &1})

    lines =
      source
      |> String.split("\n", trim: false)
      |> Enum.with_index(1)
      |> Enum.map(fn {line, line_no} ->
        line
        |> normalize_module_line(module_name, module_line, metadata[:module_exposing], line_no)
        |> normalize_import_line(import_entries_by_line, line_no)
      end)

    lines
    |> normalize_header_separator(metadata)
    |> Enum.join("\n")
    |> canonicalize_constructor_exposing_clauses()
  end

  @spec normalize_module_line(term(), term(), term(), term(), term()) :: term()
  defp normalize_module_line(line, module_name, module_line, exposing, line_no)
       when is_binary(module_name) do
    indent = leading_spaces(line)
    trimmed = String.trim_leading(line)

    cond do
      is_integer(module_line) and line_no == module_line and not is_nil(exposing) and
        usable_exposing?(exposing) and
        not String.starts_with?(trimmed, "port module ") and
        not String.starts_with?(trimmed, "effect module ") and
        not String.contains?(line, "{-") and
          not String.contains?(line, "--") ->
        indent <> "module " <> module_name <> render_exposing_clause(exposing)

      String.starts_with?(trimmed, "module ") ->
        rest = String.slice(trimmed, 7, String.length(trimmed)) |> String.trim_leading()
        {parsed_module_name, remainder} = take_import_name(rest)
        prefix = "module " <> module_name

        if parsed_module_name == module_name do
          indent <> prefix <> normalize_suffix_spacing(remainder)
        else
          line
        end

      true ->
        line
    end
  end

  defp normalize_module_line(line, _module_name, _module_line, _exposing, _line_no), do: line

  @spec normalize_import_line(term(), term(), term()) :: term()
  defp normalize_import_line(line, import_entries_by_line, line_no) do
    if leading_indent(line) != 0 do
      line
    else
      case Map.get(import_entries_by_line, line_no) do
        %{"module" => import_name} = entry ->
          if String.contains?(line, "{-") or String.contains?(line, "--") or
               not usable_exposing?(entry["exposing"]) do
            line
          else
            indent = leading_spaces(line)
            indent <> "import " <> import_name <> render_import_suffix(entry)
          end

        _ ->
          line
      end
    end
  end

  @spec normalize_suffix_spacing(term()) :: term()
  defp normalize_suffix_spacing(rest) do
    trimmed = String.trim_leading(rest)
    if trimmed == "", do: "", else: " " <> trimmed
  end

  @spec render_import_suffix(term()) :: term()
  defp render_import_suffix(entry) when is_map(entry) do
    as_clause =
      case entry["as"] do
        alias_name when is_binary(alias_name) and alias_name != "" -> " as " <> alias_name
        _ -> ""
      end

    as_clause <> render_exposing_clause(entry["exposing"])
  end

  @spec render_exposing_clause(term()) :: term()
  defp render_exposing_clause(nil), do: ""
  defp render_exposing_clause(".."), do: " exposing (..)"

  defp render_exposing_clause(items) when is_list(items) do
    rendered =
      items
      |> Enum.map(&canonicalize_exposing_item/1)
      |> Enum.map(&Doc.text/1)
      |> Doc.join(Doc.text(", "))
      |> Doc.render()

    " exposing (" <> rendered <> ")"
  end

  defp render_exposing_clause(_), do: ""

  @spec usable_exposing?(term()) :: term()
  defp usable_exposing?(nil), do: true
  defp usable_exposing?(".."), do: true

  defp usable_exposing?(items) when is_list(items) do
    Enum.all?(items, fn
      item when is_binary(item) ->
        trimmed = String.trim(item)
        trimmed != "" and trimmed != "()"

      _ ->
        false
    end)
  end

  defp usable_exposing?(_), do: false

  @spec canonicalize_exposing_item(term()) :: term()
  defp canonicalize_exposing_item(item) when is_binary(item) do
    case constructor_exposing_name(item) do
      {:ok, type_name} -> type_name <> "(..)"
      :error -> item
    end
  end

  @spec constructor_exposing_name(term()) :: term()
  defp constructor_exposing_name(item) do
    trimmed = String.trim(item)

    case String.split(trimmed, "(", parts: 2) do
      [type_name, rest] ->
        if String.ends_with?(rest, ")") and uppercase_identifier?(String.trim(type_name)) do
          inside = String.trim_trailing(rest, ")") |> String.trim()

          if constructors_list?(inside) do
            {:ok, String.trim(type_name)}
          else
            :error
          end
        else
          :error
        end

      _ ->
        :error
    end
  end

  @spec constructors_list?(term()) :: term()
  defp constructors_list?(inside) when is_binary(inside) do
    inside
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> case do
      [] -> false
      items -> Enum.all?(items, &uppercase_identifier?/1)
    end
  end

  @spec uppercase_identifier?(term()) :: term()
  defp uppercase_identifier?(value) when is_binary(value) and value != "" do
    case String.to_charlist(value) do
      [first | rest] ->
        first in ?A..?Z and Enum.all?(rest, &identifier_char?/1)

      _ ->
        false
    end
  end

  defp uppercase_identifier?(_), do: false

  @spec identifier_char?(term()) :: term()
  defp identifier_char?(c), do: c in ?A..?Z or c in ?a..?z or c in ?0..?9 or c in [?_, ?.]

  @spec leading_spaces(term()) :: term()
  defp leading_spaces(line) do
    String.slice(line, 0, leading_indent(line))
  end

  @spec leading_indent(term()) :: term()
  defp leading_indent(line) do
    String.length(line) - String.length(String.trim_leading(line))
  end

  @spec take_import_name(term()) :: term()
  defp take_import_name(rest) do
    chars = String.graphemes(rest)
    {name_chars, remaining} = Enum.split_while(chars, &import_name_char?/1)
    {Enum.join(name_chars), Enum.join(remaining)}
  end

  @spec import_name_char?(term()) :: term()
  defp import_name_char?(char) when is_binary(char) do
    case String.to_charlist(char) do
      [c] -> c in ?A..?Z or c in ?a..?z or c in ?0..?9 or c == ?. or c == ?_
      _ -> false
    end
  end

  @spec normalize_header_separator(term(), term()) :: term()
  defp normalize_header_separator(lines, metadata) when is_list(lines) and is_map(metadata) do
    module_line = get_in(metadata, [:header_lines, :module])
    import_lines = get_in(metadata, [:header_lines, :imports]) || []

    last_header_line =
      Enum.max([module_line | import_lines] |> Enum.filter(&is_integer/1), fn -> nil end)

    if is_integer(last_header_line) and length(lines) >= last_header_line + 1 do
      idx = last_header_line - 1
      current = Enum.at(lines, idx)
      next = Enum.at(lines, idx + 1)

      cond do
        is_nil(next) ->
          lines

        String.trim(current || "") == "" ->
          lines

        String.trim(next) == "" ->
          lines

        leading_indent(next) > leading_indent(current || "") ->
          lines

        true ->
          List.insert_at(lines, idx + 1, "")
      end
    else
      lines
    end
  end

  @spec canonicalize_constructor_exposing_clauses(term()) :: term()
  defp canonicalize_constructor_exposing_clauses(source) when is_binary(source) do
    rewrite_exposing_clauses(source, [])
    |> Enum.reverse()
    |> Enum.join()
  end

  @spec rewrite_exposing_clauses(term(), term()) :: term()
  defp rewrite_exposing_clauses("", acc), do: acc

  defp rewrite_exposing_clauses(<<"--", rest::binary>>, acc) do
    {comment, remaining} = take_line_comment(rest, "--")
    rewrite_exposing_clauses(remaining, [comment | acc])
  end

  defp rewrite_exposing_clauses(<<"{-", rest::binary>>, acc) do
    {comment, remaining} = take_block_comment(rest, "{-")
    rewrite_exposing_clauses(remaining, [comment | acc])
  end

  defp rewrite_exposing_clauses(<<"exposing", rest::binary>>, acc) do
    case take_bridge_to_open_paren(rest) do
      {bridge, after_open, true} ->
        case take_balanced_paren_content(after_open, [], [], false, false, false, false) do
          {:ok, inside, remaining} ->
            rewritten_inside = rewrite_constructor_lists_in_exposing(inside)
            rewritten = "exposing" <> bridge <> "(" <> rewritten_inside <> ")"
            rewrite_exposing_clauses(remaining, [rewritten | acc])

          :error ->
            rewrite_exposing_clauses(rest, ["exposing" | acc])
        end

      _ ->
        rewrite_exposing_clauses(rest, ["exposing" | acc])
    end
  end

  defp rewrite_exposing_clauses(<<char::utf8, rest::binary>>, acc) do
    rewrite_exposing_clauses(rest, [<<char::utf8>> | acc])
  end

  @spec rewrite_constructor_lists_in_exposing(term()) :: term()
  defp rewrite_constructor_lists_in_exposing(content) do
    do_rewrite_constructor_lists(content, [])
    |> Enum.reverse()
    |> Enum.join()
  end

  @spec do_rewrite_constructor_lists(term(), term()) :: term()
  defp do_rewrite_constructor_lists("", acc), do: acc

  defp do_rewrite_constructor_lists(<<"--", rest::binary>>, acc) do
    {comment, remaining} = take_line_comment(rest, "--")
    do_rewrite_constructor_lists(remaining, [comment | acc])
  end

  defp do_rewrite_constructor_lists(<<"{-", rest::binary>>, acc) do
    {comment, remaining} = take_block_comment(rest, "{-")
    do_rewrite_constructor_lists(remaining, [comment | acc])
  end

  defp do_rewrite_constructor_lists(<<char::utf8, rest::binary>>, acc) when char in ?A..?Z do
    identifier_start = <<char::utf8, rest::binary>>
    {identifier, after_identifier} = take_identifier(identifier_start)
    {bridge, after_bridge, has_open_paren?} = take_bridge_to_open_paren(after_identifier)

    if has_open_paren? do
      case take_balanced_paren_content(after_bridge, [], [], false, false, false, false) do
        {:ok, inside, remaining} ->
          if constructors_list_content?(inside) do
            replacement = identifier <> "(..)" <> trim_trailing_horizontal(bridge)
            do_rewrite_constructor_lists(remaining, [replacement | acc])
          else
            original = identifier <> bridge <> "(" <> inside <> ")"
            do_rewrite_constructor_lists(remaining, [original | acc])
          end

        :error ->
          do_rewrite_constructor_lists(after_identifier, [identifier | acc])
      end
    else
      do_rewrite_constructor_lists(after_bridge, [bridge, identifier | acc])
    end
  end

  defp do_rewrite_constructor_lists(<<char::utf8, rest::binary>>, acc) do
    do_rewrite_constructor_lists(rest, [<<char::utf8>> | acc])
  end

  @spec take_identifier(term()) :: term()
  defp take_identifier(value) when is_binary(value) do
    chars = String.graphemes(value)
    {ident_chars, remaining} = Enum.split_while(chars, &identifier_or_dot?/1)
    {Enum.join(ident_chars), Enum.join(remaining)}
  end

  @spec take_bridge_to_open_paren(term()) :: term()
  defp take_bridge_to_open_paren(value) when is_binary(value) do
    do_take_bridge_to_open_paren(value, [])
  end

  @spec do_take_bridge_to_open_paren(term(), term()) :: term()
  defp do_take_bridge_to_open_paren("", acc),
    do: {acc |> Enum.reverse() |> Enum.join(), "", false}

  defp do_take_bridge_to_open_paren(<<"--", rest::binary>>, acc) do
    {comment, remaining} = take_line_comment(rest, "--")
    do_take_bridge_to_open_paren(remaining, [comment | acc])
  end

  defp do_take_bridge_to_open_paren(<<"{-", rest::binary>>, acc) do
    {comment, remaining} = take_block_comment(rest, "{-")
    do_take_bridge_to_open_paren(remaining, [comment | acc])
  end

  defp do_take_bridge_to_open_paren(<<"(", rest::binary>>, acc),
    do: {acc |> Enum.reverse() |> Enum.join(), rest, true}

  defp do_take_bridge_to_open_paren(<<char::utf8, rest::binary>>, acc)
       when char in [?\s, ?\t, ?\n, ?\r] do
    do_take_bridge_to_open_paren(rest, [<<char::utf8>> | acc])
  end

  defp do_take_bridge_to_open_paren(value, acc),
    do: {acc |> Enum.reverse() |> Enum.join(), value, false}

  @spec take_balanced_paren_content(term(), term(), term(), term(), term(), term(), term()) ::
          term()
  defp take_balanced_paren_content(
         "",
         _stack,
         _acc,
         _in_string,
         _escape_next,
         _in_line_comment,
         _in_block_comment
       ),
       do: :error

  defp take_balanced_paren_content(
         <<char::utf8, rest::binary>>,
         stack,
         acc,
         in_string,
         escape_next,
         in_line_comment,
         in_block_comment
       ) do
    cond do
      in_line_comment and char == ?\n ->
        take_balanced_paren_content(
          rest,
          stack,
          [<<"\n">> | acc],
          in_string,
          false,
          false,
          in_block_comment
        )

      in_line_comment ->
        take_balanced_paren_content(
          rest,
          stack,
          [<<char::utf8>> | acc],
          in_string,
          false,
          true,
          in_block_comment
        )

      in_block_comment and char == ?- and String.starts_with?(rest, "}") ->
        take_balanced_paren_content(
          String.slice(rest, 1, byte_size(rest) - 1),
          stack,
          ["-}" | acc],
          in_string,
          false,
          false,
          false
        )

      in_block_comment ->
        take_balanced_paren_content(
          rest,
          stack,
          [<<char::utf8>> | acc],
          in_string,
          false,
          false,
          true
        )

      escape_next ->
        take_balanced_paren_content(
          rest,
          stack,
          [<<char::utf8>> | acc],
          in_string,
          false,
          false,
          false
        )

      in_string and char == ?\\ ->
        take_balanced_paren_content(rest, stack, [<<"\\">> | acc], in_string, true, false, false)

      char == ?" ->
        take_balanced_paren_content(
          rest,
          stack,
          [<<"\"">> | acc],
          not in_string,
          false,
          false,
          false
        )

      in_string ->
        take_balanced_paren_content(
          rest,
          stack,
          [<<char::utf8>> | acc],
          in_string,
          false,
          false,
          false
        )

      char == ?- and String.starts_with?(rest, "-") ->
        take_balanced_paren_content(
          String.slice(rest, 1, byte_size(rest) - 1),
          stack,
          ["--" | acc],
          false,
          false,
          true,
          false
        )

      char == ?{ and String.starts_with?(rest, "-") ->
        take_balanced_paren_content(
          String.slice(rest, 1, byte_size(rest) - 1),
          stack,
          ["{-" | acc],
          false,
          false,
          false,
          true
        )

      char in [?(, ?[, ?{] ->
        take_balanced_paren_content(
          rest,
          [char | stack],
          [<<char::utf8>> | acc],
          false,
          false,
          false,
          false
        )

      char in [?), ?], ?}] and stack != [] ->
        take_balanced_paren_content(
          rest,
          pop_stack(stack, char),
          [<<char::utf8>> | acc],
          false,
          false,
          false,
          false
        )

      char == ?) and stack == [] ->
        {:ok, acc |> Enum.reverse() |> Enum.join(), rest}

      true ->
        take_balanced_paren_content(
          rest,
          stack,
          [<<char::utf8>> | acc],
          false,
          false,
          false,
          false
        )
    end
  end

  @spec constructors_list_content?(term()) :: term()
  defp constructors_list_content?(inside) when is_binary(inside) do
    cleaned =
      inside
      |> strip_comments()
      |> String.trim()

    if cleaned == "" or cleaned == ".." do
      false
    else
      cleaned
      |> split_csv_simple()
      |> Enum.reject(&(&1 == ""))
      |> case do
        [] -> false
        items -> Enum.all?(items, &uppercase_identifier?/1)
      end
    end
  end

  @spec strip_comments(term()) :: term()
  defp strip_comments(value) do
    value
    |> String.split("\n", trim: false)
    |> Enum.map(fn line ->
      case :binary.match(line, "--") do
        {idx, _} -> binary_part(line, 0, idx)
        :nomatch -> line
      end
    end)
    |> Enum.join("\n")
    |> then(&remove_block_comments(&1, []))
    |> Enum.reverse()
    |> Enum.join()
  end

  @spec remove_block_comments(term(), term()) :: term()
  defp remove_block_comments("", acc), do: acc

  defp remove_block_comments(<<"{-", rest::binary>>, acc) do
    case :binary.match(rest, "-}") do
      {idx, _} ->
        remaining = binary_part(rest, idx + 2, byte_size(rest) - idx - 2)
        remove_block_comments(remaining, acc)

      :nomatch ->
        acc
    end
  end

  defp remove_block_comments(<<char::utf8, rest::binary>>, acc),
    do: remove_block_comments(rest, [<<char::utf8>> | acc])

  @spec split_csv_simple(term()) :: term()
  defp split_csv_simple(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
  end

  @spec take_line_comment(term(), term()) :: term()
  defp take_line_comment(value, prefix) do
    case :binary.match(value, "\n") do
      {idx, _} ->
        comment = prefix <> binary_part(value, 0, idx + 1)
        remaining = binary_part(value, idx + 1, byte_size(value) - idx - 1)
        {comment, remaining}

      :nomatch ->
        {prefix <> value, ""}
    end
  end

  @spec take_block_comment(term(), term()) :: term()
  defp take_block_comment(value, prefix) do
    case :binary.match(value, "-}") do
      {idx, _} ->
        comment = prefix <> binary_part(value, 0, idx + 2)
        remaining = binary_part(value, idx + 2, byte_size(value) - idx - 2)
        {comment, remaining}

      :nomatch ->
        {prefix <> value, ""}
    end
  end

  @spec identifier_or_dot?(term()) :: term()
  defp identifier_or_dot?(char) when is_binary(char) do
    case String.to_charlist(char) do
      [c] -> c in ?A..?Z or c in ?a..?z or c in ?0..?9 or c in [?_, ?., ?']
      _ -> false
    end
  end

  @spec trim_trailing_horizontal(term()) :: term()
  defp trim_trailing_horizontal(value) when is_binary(value) do
    value
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 in [" ", "\t", "\n", "\r"]))
    |> Enum.reverse()
    |> Enum.join()
  end

  @spec pop_stack(term(), term()) :: term()
  defp pop_stack([], _closing), do: []

  defp pop_stack([open | rest], closing) do
    if delimiter_char_match?(open, closing), do: rest, else: [open | rest]
  end

  @spec delimiter_char_match?(term(), term()) :: term()
  defp delimiter_char_match?(?(, ?)), do: true
  defp delimiter_char_match?(?[, ?]), do: true
  defp delimiter_char_match?(?{, ?}), do: true
  defp delimiter_char_match?(_, _), do: false
end
