defmodule Ide.Formatter.Printer.List do
  @moduledoc false
  alias Ide.Formatter.Semantics.Rules

  @spec normalize_item_splits(String.t(), [map()] | nil) :: String.t()
  def normalize_item_splits(source, tokens) when is_binary(source) and is_list(tokens) do
    split_targets = list_item_split_targets(tokens)

    source
    |> String.split("\n", trim: false)
    |> Enum.with_index(1)
    |> Enum.map(fn {line, line_no} ->
      case Map.get(split_targets, line_no) do
        nil ->
          line

        [] ->
          line

        splits ->
          splits
          |> Enum.sort_by(& &1.column, :desc)
          |> Enum.reduce(line, fn split, current ->
            split_line_before_column(current, split.column, split.indent)
          end)
      end
    end)
    |> Enum.join("\n")
  end

  def normalize_item_splits(source, _tokens) when is_binary(source) do
    {normalized_rev, _inside_multiline_list, _list_indent} =
      source
      |> String.split("\n", trim: false)
      |> Enum.reduce({[], false, nil}, fn line, {acc, inside_multiline_list, list_indent} ->
        {normalized, next_inside, next_indent} =
          normalize_item_split_line_without_tokens(line, inside_multiline_list, list_indent)

        {[normalized | acc], next_inside, next_indent}
      end)

    normalized_rev
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  @spec normalize_inline_long_lists(String.t()) :: String.t()
  def normalize_inline_long_lists(source) when is_binary(source) do
    source
    |> String.split("\n", trim: false)
    |> Enum.map(&expand_inline_list_line/1)
    |> List.flatten()
    |> Enum.join("\n")
  end

  @spec normalize_opening_line_items(String.t()) :: String.t()
  def normalize_opening_line_items(source) when is_binary(source) do
    source
    |> String.split("\n", trim: false)
    |> Enum.map(&expand_opening_line_with_multiple_items/1)
    |> List.flatten()
    |> Enum.join("\n")
  end

  @spec normalize_opening_indentation(String.t(), [map()] | nil) :: String.t()
  def normalize_opening_indentation(source, tokens) when is_binary(source) and is_list(tokens) do
    {normalized_rev, _prev_indent} =
      source
      |> String.split("\n", trim: false)
      |> Enum.reduce({[], nil}, fn line, {acc, prev_indent} ->
        trimmed = String.trim(line)

        normalized =
          if starts_with_trimmed?(line, "[") and not String.contains?(line, "]") and
               is_integer(prev_indent) do
            expected = prev_indent + Rules.indent_width()
            String.duplicate(" ", expected) <> String.trim_leading(line)
          else
            line
          end

        next_prev_indent =
          if trimmed == "" do
            prev_indent
          else
            leading_indent(normalized)
          end

        {[normalized | acc], next_prev_indent}
      end)

    normalized_rev
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  def normalize_opening_indentation(source, _tokens), do: source

  @spec normalize_closing_bracket_lines(String.t()) :: String.t()
  def normalize_closing_bracket_lines(source) when is_binary(source) do
    {lines_rev, _list_indent} =
      source
      |> String.split("\n", trim: false)
      |> Enum.reduce({[], nil}, fn line, {acc, list_indent} ->
        opening_indent = opening_list_indent(line)

        cond do
          is_nil(list_indent) and is_integer(opening_indent) ->
            {[line | acc], opening_indent}

          is_integer(list_indent) and starts_with_trimmed?(line, ",") ->
            case split_line_before_top_level_close_bracket(line, list_indent) do
              {:split, item_line, closing_line} ->
                {[closing_line, item_line | acc], nil}

              :no_change ->
                {[line | acc], list_indent}
            end

          is_integer(list_indent) and starts_with_trimmed?(line, "]") ->
            {[line | acc], nil}

          true ->
            {[line | acc], list_indent}
        end
      end)

    lines_rev
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  @spec normalize_alignment(String.t(), [map()] | nil) :: String.t()
  def normalize_alignment(source, _tokens) when is_binary(source) do
    {normalized_rev, _indent_stack} =
      source
      |> String.split("\n", trim: false)
      |> Enum.reduce({[], []}, fn line, {acc, indent_stack} ->
        trimmed = String.trim_leading(line)
        current_indent = leading_indent(line)
        opening_indents = opening_list_indents(line)

        cond do
          opening_indents != [] ->
            {[line | acc], opening_indents ++ indent_stack}

          indent_stack != [] and starts_with_trimmed?(line, ",") and
              current_indent <= hd(indent_stack) + 1 ->
            normalized = String.duplicate(" ", hd(indent_stack)) <> trimmed
            {[normalized | acc], indent_stack}

          indent_stack != [] and starts_with_trimmed?(line, "]") ->
            normalized = String.duplicate(" ", hd(indent_stack)) <> trimmed
            {[normalized | acc], tl(indent_stack)}

          true ->
            {[line | acc], indent_stack}
        end
      end)

    normalized_rev
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  @spec list_item_split_targets(term()) :: term()
  defp list_item_split_targets(tokens) do
    ordered =
      tokens
      |> Enum.filter(fn token ->
        is_map(token) and is_binary(token[:text]) and is_integer(token[:line]) and
          is_integer(token[:column])
      end)
      |> Enum.sort_by(fn token -> {token.line, token.column} end)

    {_, _first_comma_by_line, split_targets} =
      Enum.reduce(ordered, {[], %{}, %{}}, fn token,
                                              {stack, first_comma_by_line, split_targets} ->
        text = token.text

        cond do
          text in ["[", "(", "{"] ->
            {[text | stack], first_comma_by_line, split_targets}

          text in ["]", ")", "}"] ->
            {pop_delimiter(stack, text), first_comma_by_line, split_targets}

          text == "," and stack != [] and hd(stack) == "[" ->
            line = token.line

            case Map.get(first_comma_by_line, line) do
              nil ->
                {stack, Map.put(first_comma_by_line, line, token.column - 1), split_targets}

              indent ->
                next_targets =
                  Map.update(
                    split_targets,
                    line,
                    [%{column: token.column, indent: indent}],
                    fn items ->
                      [%{column: token.column, indent: indent} | items]
                    end
                  )

                {stack, first_comma_by_line, next_targets}
            end

          true ->
            {stack, first_comma_by_line, split_targets}
        end
      end)

    split_targets
  end

  @spec split_line_before_column(term(), term(), term()) :: term()
  defp split_line_before_column(line, column, indent)
       when is_binary(line) and is_integer(column) do
    split_idx = max(column - 1, 0)

    if split_idx >= String.length(line) do
      line
    else
      left = String.slice(line, 0, split_idx) |> String.trim_trailing()

      right =
        String.slice(line, split_idx, String.length(line) - split_idx) |> String.trim_leading()

      left <> "\n" <> String.duplicate(" ", max(indent, 0)) <> right
    end
  end

  @spec pop_delimiter(term(), term()) :: term()
  defp pop_delimiter([], _close), do: []

  defp pop_delimiter([open | rest], close) do
    if delimiters_match?(open, close), do: rest, else: [open | rest]
  end

  @spec delimiters_match?(term(), term()) :: term()
  defp delimiters_match?("[", "]"), do: true
  defp delimiters_match?("(", ")"), do: true
  defp delimiters_match?("{", "}"), do: true
  defp delimiters_match?(_, _), do: false

  @spec starts_with_trimmed?(term(), term()) :: term()
  defp starts_with_trimmed?(line, marker),
    do: String.starts_with?(String.trim_leading(line), marker)

  @spec leading_indent(term()) :: term()
  defp leading_indent(line) do
    String.length(line) - String.length(String.trim_leading(line))
  end

  @spec split_line_before_top_level_close_bracket(term(), term()) :: term()
  defp split_line_before_top_level_close_bracket(line, list_indent) do
    case list_item_close_bracket_index(line) do
      nil ->
        :no_change

      idx ->
        left = String.slice(line, 0, idx) |> String.trim_trailing()
        right = String.slice(line, idx + 1, String.length(line) - idx - 1) |> String.trim()

        if left == "" do
          :no_change
        else
          closing_line =
            if right == "" do
              String.duplicate(" ", list_indent) <> "]"
            else
              String.duplicate(" ", list_indent) <> "] " <> right
            end

          {:split, left, closing_line}
        end
    end
  end

  @spec expand_inline_list_line(term()) :: term()
  defp expand_inline_list_line(line) do
    cond do
      String.length(line) < 88 ->
        [line]

      String.contains?(line, "--") ->
        [line]

      true ->
        case split_inline_list(line) do
          {:ok, prefix, items, suffix, list_indent} when length(items) >= 2 ->
            first = hd(items)
            rest = tl(items)

            item_lines =
              rest
              |> Enum.map(fn item -> String.duplicate(" ", list_indent) <> ", " <> item end)

            closing =
              if suffix == "" do
                String.duplicate(" ", list_indent) <> "]"
              else
                String.duplicate(" ", list_indent) <> "]" <> suffix
              end

            [prefix, String.duplicate(" ", list_indent) <> "[ " <> first] ++
              item_lines ++ [closing]

          _ ->
            [line]
        end
    end
  end

  @spec split_inline_list(term()) :: term()
  defp split_inline_list(line) do
    with {:ok, open_idx, close_idx} <- top_level_list_bounds(line),
         true <- open_idx > 0 do
      prefix = String.slice(line, 0, open_idx) |> String.trim_trailing()
      inside = String.slice(line, open_idx + 1, close_idx - open_idx - 1)
      suffix = String.slice(line, close_idx + 1, String.length(line) - close_idx - 1)
      items = split_top_level_csv(inside)
      list_indent = leading_indent(line) + Rules.indent_width()

      if prefix == "" or Enum.any?(items, &(&1 == "")) or String.contains?(prefix, "=") do
        :error
      else
        {:ok, prefix, items, suffix, list_indent}
      end
    else
      _ -> :error
    end
  end

  @spec expand_opening_line_with_multiple_items(term()) :: term()
  defp expand_opening_line_with_multiple_items(line) do
    case split_opening_line_first_comma(line) do
      {:ok, prefix, first_item, remainder, indent} ->
        [
          prefix,
          String.duplicate(" ", indent) <> "[ " <> first_item,
          String.duplicate(" ", indent) <> ", " <> remainder
        ]

      :error ->
        [line]
    end
  end

  @spec split_opening_line_first_comma(term()) :: term()
  defp split_opening_line_first_comma(line) do
    trimmed = String.trim_leading(line)

    if String.contains?(trimmed, "[") and not String.contains?(trimmed, "]") do
      case first_list_comma_index(line) do
        {:ok, open_idx, comma_idx} when comma_idx > open_idx ->
          prefix = String.slice(line, 0, open_idx) |> String.trim_trailing()

          first_item =
            String.slice(line, open_idx + 1, comma_idx - open_idx - 1)
            |> String.trim()

          remainder =
            String.slice(line, comma_idx + 1, String.length(line) - comma_idx - 1)
            |> String.trim()

          if prefix == "" or first_item == "" or remainder == "" do
            :error
          else
            {:ok, prefix, first_item, remainder, leading_indent(line) + Rules.indent_width()}
          end

        _ ->
          :error
      end
    else
      :error
    end
  end

  @spec first_list_comma_index(term()) :: term()
  defp first_list_comma_index(line) do
    do_first_list_comma_index(line, [], false, false, 0, nil)
  end

  @spec do_first_list_comma_index(term(), term(), term(), term(), term(), term()) :: term()
  defp do_first_list_comma_index("", _stack, _in_string, _escape_next, _idx, _open_idx),
    do: :error

  defp do_first_list_comma_index(
         <<char::utf8, rest::binary>>,
         stack,
         in_string,
         escape_next,
         idx,
         open_idx
       ) do
    cond do
      escape_next ->
        do_first_list_comma_index(rest, stack, in_string, false, idx + 1, open_idx)

      in_string and char == ?\\ ->
        do_first_list_comma_index(rest, stack, in_string, true, idx + 1, open_idx)

      char == ?" ->
        do_first_list_comma_index(rest, stack, not in_string, false, idx + 1, open_idx)

      in_string ->
        do_first_list_comma_index(rest, stack, in_string, false, idx + 1, open_idx)

      char in [?(, ?{] ->
        do_first_list_comma_index(rest, [char | stack], false, false, idx + 1, open_idx)

      char == ?[ and is_nil(open_idx) and stack == [] ->
        do_first_list_comma_index(rest, [char | stack], false, false, idx + 1, idx)

      char == ?[ ->
        do_first_list_comma_index(rest, [char | stack], false, false, idx + 1, open_idx)

      char in [?), ?}, ?]] and stack != [] ->
        do_first_list_comma_index(rest, pop_stack(stack, char), false, false, idx + 1, open_idx)

      char == ?, and stack == [?[] and is_integer(open_idx) ->
        {:ok, open_idx, idx}

      true ->
        do_first_list_comma_index(rest, stack, false, false, idx + 1, open_idx)
    end
  end

  @spec split_top_level_csv(term()) :: term()
  defp split_top_level_csv(value) do
    {parts, current, _stack, _in_string, _escape_next} =
      do_split_top_level_csv(value, [], "", [], false, false)

    parts = parts ++ [String.trim(current)]
    Enum.reject(parts, &(&1 == ""))
  end

  @spec do_split_top_level_csv(term(), term(), term(), term(), term(), term()) :: term()
  defp do_split_top_level_csv("", parts, current, stack, in_string, escape_next),
    do: {parts, current, stack, in_string, escape_next}

  defp do_split_top_level_csv(
         <<char::utf8, rest::binary>>,
         parts,
         current,
         stack,
         in_string,
         escape_next
       ) do
    cond do
      escape_next ->
        do_split_top_level_csv(rest, parts, current <> <<char::utf8>>, stack, in_string, false)

      in_string and char == ?\\ ->
        do_split_top_level_csv(rest, parts, current <> <<char::utf8>>, stack, in_string, true)

      char == ?" ->
        do_split_top_level_csv(
          rest,
          parts,
          current <> <<char::utf8>>,
          stack,
          not in_string,
          false
        )

      in_string ->
        do_split_top_level_csv(rest, parts, current <> <<char::utf8>>, stack, in_string, false)

      char in [?(, ?[, ?{] ->
        do_split_top_level_csv(
          rest,
          parts,
          current <> <<char::utf8>>,
          [char | stack],
          false,
          false
        )

      char in [?), ?], ?}] ->
        do_split_top_level_csv(
          rest,
          parts,
          current <> <<char::utf8>>,
          pop_stack(stack, char),
          false,
          false
        )

      char == ?, and stack == [] ->
        do_split_top_level_csv(rest, parts ++ [String.trim(current)], "", stack, false, false)

      true ->
        do_split_top_level_csv(rest, parts, current <> <<char::utf8>>, stack, false, false)
    end
  end

  @spec top_level_list_bounds(term()) :: term()
  defp top_level_list_bounds(line) do
    do_top_level_list_bounds(line, [], false, false, 0, nil)
  end

  @spec do_top_level_list_bounds(term(), term(), term(), term(), term(), term()) :: term()
  defp do_top_level_list_bounds("", _stack, _in_string, _escape_next, _idx, _open_idx), do: :error

  defp do_top_level_list_bounds(
         <<char::utf8, rest::binary>>,
         stack,
         in_string,
         escape_next,
         idx,
         open_idx
       ) do
    cond do
      escape_next ->
        do_top_level_list_bounds(rest, stack, in_string, false, idx + 1, open_idx)

      in_string and char == ?\\ ->
        do_top_level_list_bounds(rest, stack, in_string, true, idx + 1, open_idx)

      char == ?" ->
        do_top_level_list_bounds(rest, stack, not in_string, false, idx + 1, open_idx)

      in_string ->
        do_top_level_list_bounds(rest, stack, in_string, false, idx + 1, open_idx)

      char in [?(, ?{] ->
        do_top_level_list_bounds(rest, [char | stack], false, false, idx + 1, open_idx)

      char == ?[ and stack == [] and is_nil(open_idx) ->
        do_top_level_list_bounds(rest, [char | stack], false, false, idx + 1, idx)

      char == ?[ ->
        do_top_level_list_bounds(rest, [char | stack], false, false, idx + 1, open_idx)

      char in [?), ?}, ?]] and stack != [] ->
        next_stack = pop_stack(stack, char)

        if char == ?] and stack == [?[] and is_integer(open_idx) do
          {:ok, open_idx, idx}
        else
          do_top_level_list_bounds(rest, next_stack, false, false, idx + 1, open_idx)
        end

      true ->
        do_top_level_list_bounds(rest, stack, false, false, idx + 1, open_idx)
    end
  end

  @spec normalize_item_split_line_without_tokens(term(), term(), term()) :: term()
  defp normalize_item_split_line_without_tokens(line, inside_multiline_list, list_indent) do
    trimmed = String.trim(line)
    leading = leading_indent(line)
    open_count = visible_char_count(line, ?[)
    close_count = visible_char_count(line, ?])

    cond do
      not inside_multiline_list and open_count > close_count ->
        indent = leading
        {line, true, indent}

      inside_multiline_list and close_count > open_count ->
        normalized = split_line_at_extra_top_level_commas(line, list_indent || leading)
        {normalized, false, nil}

      inside_multiline_list and trimmed != "" ->
        normalized = split_line_at_extra_top_level_commas(line, list_indent || leading)
        {normalized, true, list_indent}

      true ->
        {line, inside_multiline_list, list_indent}
    end
  end

  @spec split_line_at_extra_top_level_commas(term(), term()) :: term()
  defp split_line_at_extra_top_level_commas(line, indent) do
    comma_columns = top_level_comma_columns(line)

    case comma_columns do
      [_] ->
        line

      [_first | rest] ->
        rest
        |> Enum.sort(:desc)
        |> Enum.reduce(line, fn column, current ->
          split_line_before_column(current, column, indent)
        end)

      _ ->
        line
    end
  end

  @spec top_level_comma_columns(term()) :: term()
  defp top_level_comma_columns(line) do
    line
    |> scan_top_level([], false, false, 1, %{char: ?,, columns: []})
    |> Map.get(:columns, [])
  end

  @spec list_item_close_bracket_index(term()) :: term()
  defp list_item_close_bracket_index(line) do
    do_list_item_close_bracket_index(line, [], false, false, 0)
  end

  @spec do_list_item_close_bracket_index(term(), term(), term(), term(), term()) :: term()
  defp do_list_item_close_bracket_index("", _stack, _in_string, _escape_next, _idx), do: nil

  defp do_list_item_close_bracket_index(
         <<char::utf8, rest::binary>>,
         stack,
         in_string,
         escape_next,
         idx
       ) do
    cond do
      escape_next ->
        do_list_item_close_bracket_index(rest, stack, in_string, false, idx + 1)

      in_string and char == ?\\ ->
        do_list_item_close_bracket_index(rest, stack, in_string, true, idx + 1)

      char == ?" ->
        do_list_item_close_bracket_index(rest, stack, not in_string, false, idx + 1)

      in_string ->
        do_list_item_close_bracket_index(rest, stack, in_string, false, idx + 1)

      char in [?(, ?[, ?{] ->
        do_list_item_close_bracket_index(rest, [char | stack], false, false, idx + 1)

      char in [?), ?}] ->
        do_list_item_close_bracket_index(rest, pop_stack(stack, char), false, false, idx + 1)

      char == ?] and stack == [] ->
        idx

      char == ?] ->
        do_list_item_close_bracket_index(rest, pop_stack(stack, char), false, false, idx + 1)

      true ->
        do_list_item_close_bracket_index(rest, stack, false, false, idx + 1)
    end
  end

  @spec visible_char_count(term(), term()) :: term()
  defp visible_char_count(line, char_code) when is_binary(line) and is_integer(char_code) do
    do_visible_char_count(line, char_code, 0, false, false)
  end

  @spec do_visible_char_count(term(), term(), term(), term(), term()) :: term()
  defp do_visible_char_count("", _char_code, count, _in_string, _escape_next), do: count

  defp do_visible_char_count(
         <<char::utf8, rest::binary>>,
         char_code,
         count,
         in_string,
         escape_next
       ) do
    cond do
      escape_next ->
        do_visible_char_count(rest, char_code, count, in_string, false)

      in_string and char == ?\\ ->
        do_visible_char_count(rest, char_code, count, in_string, true)

      char == ?" ->
        do_visible_char_count(rest, char_code, count, not in_string, false)

      in_string ->
        do_visible_char_count(rest, char_code, count, in_string, false)

      char == char_code ->
        do_visible_char_count(rest, char_code, count + 1, false, false)

      true ->
        do_visible_char_count(rest, char_code, count, false, false)
    end
  end

  @spec scan_top_level(term(), term(), term(), term(), term(), term()) :: term()
  defp scan_top_level("", _stack, _in_string, _escape_next, _col, result), do: result

  defp scan_top_level(<<char::utf8, rest::binary>>, stack, in_string, escape_next, col, result) do
    cond do
      escape_next ->
        scan_top_level(rest, stack, in_string, false, col + 1, result)

      in_string and char == ?\\ ->
        scan_top_level(rest, stack, in_string, true, col + 1, result)

      char == ?" ->
        scan_top_level(rest, stack, not in_string, false, col + 1, result)

      in_string ->
        scan_top_level(rest, stack, in_string, false, col + 1, result)

      char in [?(, ?[, ?{] ->
        scan_top_level(rest, [char | stack], false, false, col + 1, result)

      char in [?), ?], ?}] ->
        scan_top_level(rest, pop_stack(stack, char), false, false, col + 1, result)

      stack == [] and char == result.char ->
        next = %{result | columns: result.columns ++ [col]}
        scan_top_level(rest, stack, false, false, col + 1, next)

      true ->
        scan_top_level(rest, stack, false, false, col + 1, result)
    end
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

  @spec opening_list_indent(term()) :: term()
  defp opening_list_indent(line) do
    case opening_list_indents(line) do
      [indent | _] -> indent
      _ -> nil
    end
  end

  @spec opening_list_indents(term()) :: term()
  defp opening_list_indents(line) do
    do_opening_list_indent(line, 0, [], false, false)
    |> Enum.filter(fn {char, _pos} -> char == ?[ end)
    |> Enum.map(fn {_, pos} -> pos end)
  end

  @spec do_opening_list_indent(term(), term(), term(), term(), term()) :: term()
  defp do_opening_list_indent("", _col, stack, _in_string, _escape_next) do
    stack
  end

  defp do_opening_list_indent(<<char::utf8, rest::binary>>, col, stack, in_string, escape_next) do
    cond do
      escape_next ->
        do_opening_list_indent(rest, col + 1, stack, in_string, false)

      in_string and char == ?\\ ->
        do_opening_list_indent(rest, col + 1, stack, in_string, true)

      char == ?" ->
        do_opening_list_indent(rest, col + 1, stack, not in_string, false)

      in_string ->
        do_opening_list_indent(rest, col + 1, stack, in_string, false)

      char in [?(, ?{] ->
        do_opening_list_indent(rest, col + 1, [{char, col} | stack], false, false)

      char == ?[ ->
        do_opening_list_indent(rest, col + 1, [{char, col} | stack], false, false)

      char in [?), ?], ?}] ->
        do_opening_list_indent(rest, col + 1, pop_opening_indent_stack(stack, char), false, false)

      true ->
        do_opening_list_indent(rest, col + 1, stack, false, false)
    end
  end

  @spec pop_opening_indent_stack(term(), term()) :: term()
  defp pop_opening_indent_stack([], _closing), do: []

  defp pop_opening_indent_stack([{open, pos} | rest], closing) do
    if delimiter_char_match?(open, closing), do: rest, else: [{open, pos} | rest]
  end
end
