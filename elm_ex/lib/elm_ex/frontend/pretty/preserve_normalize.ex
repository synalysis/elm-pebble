defmodule ElmEx.Frontend.Pretty.PreserveNormalize do
  @moduledoc false

  alias ElmEx.Frontend.Module

  @spec normalize_regions(map(), Module.t()) :: map()
  def normalize_regions(regions, %Module{} = mod) when is_map(regions) do
    %{
      regions
      | preamble: normalize_whitespace(regions.preamble),
        header:
          regions.header
          |> normalize_whitespace()
          |> normalize_legacy_module_header()
          |> normalize_multiline_exposing_blocks()
          |> collapse_header_exposing_constructors(),
        pre_import: normalize_whitespace(regions.pre_import),
        imports:
          regions.imports
          |> normalize_imports(mod.import_entries),
        pre_body: normalize_whitespace(regions.pre_body)
    }
  end

  @spec normalize_imports(String.t(), [map()]) :: String.t()
  defp normalize_imports(imports, _import_entries) when is_binary(imports) do
    imports
    |> collapse_detected_exposing_constructors(:import)
    |> normalize_exposing_comma_indents()
    |> normalize_whitespace()
  end

  @spec collapse_header_exposing_constructors(String.t()) :: String.t()
  defp collapse_header_exposing_constructors(text) when is_binary(text) do
    collapse_detected_exposing_constructors(text, :header)
  end

  @spec collapse_detected_exposing_constructors(String.t(), :import | :header) :: String.t()
  defp collapse_detected_exposing_constructors(text, mode) when is_binary(text) do
    text
    |> strip_comments_for_type_scan()
    |> candidate_union_exposing_types()
    |> Enum.reduce(text, fn type, acc ->
      collapsed = collapse_type_exposing(acc, type, mode)

      if collapsed == acc, do: acc, else: collapsed
    end)
  end

  @spec strip_comments_for_type_scan(String.t()) :: String.t()
  defp strip_comments_for_type_scan(text) when is_binary(text) do
    text
    |> String.replace(~r/--[^\n]*/u, "")
    |> String.replace(~r/\{-[^}]*-\}/u, "")
  end

  @spec normalize_exposing_comma_indents(String.t()) :: String.t()
  defp normalize_exposing_comma_indents(text) when is_binary(text) do
    {lines, _} =
      Enum.map_reduce(String.split(text, "\n", trim: false), nil, fn line, current_indent ->
        trimmed = String.trim_leading(line)

        cond do
          Regex.match?(~r/^\(\s*/u, trimmed) ->
            {line, leading_indent(line)}

          current_indent != nil and String.starts_with?(trimmed, ",") ->
            {String.duplicate(" ", current_indent) <> trimmed, current_indent}

          Regex.match?(~r/^\)\s*$/u, trimmed) ->
            {line, nil}

          true ->
            {line, current_indent}
        end
      end)

    Enum.join(lines, "\n")
  end
  defp candidate_union_exposing_types(text) when is_binary(text) do
    ~r/\b([A-Z][A-Za-z0-9_']*)\b\s*(?:\((?!\.\.)|\n[ \t]*\()/u
    |> Regex.scan(text)
    |> Enum.map(fn [_, type] -> type end)
    |> Enum.uniq()
  end

  @spec collapse_type_exposing(String.t(), String.t(), :import | :header) :: String.t()
  defp collapse_type_exposing(text, type_name, mode) when is_binary(type_name) do
    case find_type_exposing_span(text, type_name) do
      {start, finish, gap_before, gap_after, inner} ->
        if should_collapse_exposing?(inner, gap_before, text, start, finish, mode) do
          type_indent =
            text
            |> String.slice(0, start)
            |> String.split("\n")
            |> List.last()
            |> leading_indent()

          gap_before = normalize_gap_comment_indent(gap_before, type_indent)
          gap_after = normalize_gap_comment_indent(gap_after, type_indent)

          after_part =
            text
            |> String.slice(finish..-1//1)
            |> trim_leading_if_gap_ends_with_space(gap_before <> gap_after)

          String.slice(text, 0, start) <>
            type_name <> "(..)" <> gap_before <> String.trim_leading(gap_after) <> after_part
        else
          text
        end

      :error ->
        text
    end
  end

  @spec should_collapse_exposing?(String.t(), String.t(), String.t(), non_neg_integer(), non_neg_integer(), :import | :header) ::
          boolean()
  defp should_collapse_exposing?(inner, gap_before, text, start, finish, mode) do
    span = String.slice(text, start, finish - start + 1)
    multiline? = String.contains?(span, "\n")
    gapped? = String.trim(gap_before) != ""
    multi_constructor? = inner |> strip_comments_for_type_scan() |> String.contains?(",")

    case mode do
      :import -> multiline? or gapped? or multi_constructor?
      :header -> true
    end
  end

  @spec normalize_gap_comment_indent(String.t(), non_neg_integer()) :: String.t()
  defp normalize_gap_comment_indent("", _indent), do: ""
  defp normalize_gap_comment_indent(gap, 0), do: gap

  defp normalize_gap_comment_indent(gap, indent) when indent > 0 do
    prefix = String.duplicate(" ", indent)

    gap
    |> String.split("\n", trim: false)
    |> Enum.map(fn
      "" -> ""
      line -> prefix <> String.trim_leading(line)
    end)
    |> Enum.join("\n")
  end

  @spec trim_leading_if_gap_ends_with_space(String.t(), String.t()) :: String.t()
  defp trim_leading_if_gap_ends_with_space(after_part, gap) do
    if String.match?(gap, ~r/\s\z/u) and String.match?(after_part, ~r/^\s+/u) do
      String.trim_leading(after_part)
    else
      after_part
    end
  end

  @spec find_type_exposing_span(String.t(), String.t()) ::
          {non_neg_integer(), non_neg_integer(), String.t(), String.t(), String.t()} | :error
  defp find_type_exposing_span(text, type_name) do
    pattern = ~r/\b#{Regex.escape(type_name)}\b/u

    pattern
    |> Regex.scan(text, return: :index)
    |> Enum.reduce_while(:error, fn
      [{start, len}], :error ->
        case try_type_exposing_at(text, start, len) do
          :error -> {:cont, :error}
          ok -> {:halt, ok}
        end

      _, acc ->
        {:halt, acc}
    end)
  end

  @spec try_type_exposing_at(String.t(), non_neg_integer(), pos_integer()) ::
          {non_neg_integer(), non_neg_integer(), String.t(), String.t(), String.t()} | :error
  defp try_type_exposing_at(text, start, len) do
    after_type = start + len
    {gap_before, open_pos} = consume_gap(text, after_type)

    cond do
      String.contains?(gap_before, "exposing") ->
        :error

      String.at(text, open_pos) != "(" ->
        :error

      true ->
        case take_balanced(text, open_pos) do
          {inner, close_pos} ->
            finish = close_pos + 1
            {gap_after, _} = consume_comment_only_gap(text, finish)

            if constructor_exposing_parens?(inner) do
              {start, finish + String.length(gap_after), gap_before, gap_after, inner}
            else
              :error
            end

          :error ->
            :error
        end
    end
  end

  @spec constructor_exposing_parens?(String.t()) :: boolean()
  defp constructor_exposing_parens?(inner) when is_binary(inner) do
    stripped =
      inner
      |> String.replace(~r/\{-[^}]*-\}/u, "")
      |> String.trim()

    stripped != "" and not String.contains?(stripped, "import")
  end

  @spec consume_gap(String.t(), non_neg_integer()) :: {String.t(), non_neg_integer()}
  defp consume_gap(text, pos) do
    do_consume_gap(text, pos, "")
  end

  defp do_consume_gap(text, pos, acc) do
    case String.at(text, pos) do
      nil ->
        {acc, pos}

      c when c in [" ", "\t", "\n", "\r"] ->
        do_consume_gap(text, pos + 1, acc <> c)

      "-" ->
        case line_comment_at(text, pos) do
          {comment, next} -> do_consume_gap(text, next, acc <> comment)
          :error -> {acc, pos}
        end

      "{" ->
        case block_comment_at(text, pos) do
          {comment, next} -> do_consume_gap(text, next, acc <> comment)
          :error -> {acc, pos}
        end

      _ ->
        {acc, pos}
    end
  end

  @spec consume_comment_only_gap(String.t(), non_neg_integer()) :: {String.t(), non_neg_integer()}
  defp consume_comment_only_gap(text, pos) do
    do_consume_comment_only_gap(text, pos, "")
  end

  defp do_consume_comment_only_gap(text, pos, acc) do
    case String.at(text, pos) do
      nil ->
        {acc, pos}

      c when c in [" ", "\t", "\n", "\r"] ->
        do_consume_comment_only_gap(text, pos + 1, acc <> c)

      "-" ->
        case line_comment_at(text, pos) do
          {comment, next} -> do_consume_comment_only_gap(text, next, acc <> comment)
          :error -> {acc, pos}
        end

      "{" ->
        case block_comment_at(text, pos) do
          {comment, next} -> do_consume_comment_only_gap(text, next, acc <> comment)
          :error -> {acc, pos}
        end

      "," ->
        {acc, pos}

      _ ->
        {acc, pos}
    end
  end

  @spec line_comment_at(String.t(), non_neg_integer()) :: {String.t(), non_neg_integer()} | :error
  defp line_comment_at(text, pos) do
    case Regex.run(~r/\A--[^\n]*/u, String.slice(text, pos..-1//1), capture: :first) do
      [comment] -> {comment, pos + byte_size(comment)}
      _ -> :error
    end
  end

  @spec block_comment_at(String.t(), non_neg_integer()) :: {String.t(), non_neg_integer()} | :error
  defp block_comment_at(text, pos) do
    case Regex.run(~r/\A(\{-[^}]*-\})/u, String.slice(text, pos..-1//1), capture: :first) do
      [comment] -> {comment, pos + byte_size(comment)}
      _ -> :error
    end
  end

  @spec take_balanced(String.t(), non_neg_integer()) :: {String.t(), non_neg_integer()} | :error
  defp take_balanced(text, open_pos) do
    case String.at(text, open_pos) do
      "(" -> do_take_balanced(text, open_pos + 1, 1, "")
      _ -> :error
    end
  end

  defp do_take_balanced(text, pos, depth, acc) when depth > 0 do
    case String.at(text, pos) do
      nil ->
        :error

      "(" ->
        do_take_balanced(text, pos + 1, depth + 1, acc <> "(")

      ")" ->
        if depth == 1 do
          {acc, pos}
        else
          do_take_balanced(text, pos + 1, depth - 1, acc <> ")")
        end

      "{-" ->
        case Regex.run(~r/\A(\{-[^}]*-\})/u, String.slice(text, pos..-1//1), capture: :first) do
          [comment] ->
            do_take_balanced(text, pos + byte_size(comment), depth, acc <> comment)

          _ ->
            do_take_balanced(text, pos + 2, depth, acc <> "{-")
        end

      char ->
        do_take_balanced(text, pos + 1, depth, acc <> char)
    end
  end

  defp do_take_balanced(_text, _pos, 0, _acc), do: :error

  @spec normalize_legacy_module_header(String.t()) :: String.t()
  defp normalize_legacy_module_header(""), do: ""

  defp normalize_legacy_module_header(text) when is_binary(text) do
    text
    |> String.split("\n", trim: false)
    |> Enum.map_join("\n", &normalize_legacy_module_header_line/1)
  end

  @spec normalize_legacy_module_header_line(String.t()) :: String.t()
  defp normalize_legacy_module_header_line(line) when is_binary(line) do
    trimmed = String.trim_trailing(line)

    case Regex.run(
           ~r/^(\s*(?:port\s+|effect\s+)?module\s+\S+)\s+\(\.\.\)\s+where\s*$/u,
           trimmed
         ) do
      [_, prefix] -> prefix <> " exposing (..)"
      _ -> line
    end
  end

  @spec normalize_whitespace(String.t()) :: String.t()
  defp normalize_whitespace(text) when is_binary(text) do
    text
    |> String.split("\n", trim: false)
    |> Enum.map_join("\n", &normalize_line_whitespace/1)
  end

  @spec normalize_line_whitespace(String.t()) :: String.t()
  defp normalize_line_whitespace(line) when is_binary(line) do
    line
    |> String.replace(~r/\(\s{2,}/u, "( ")
    |> String.replace(~r/,\s{2,}/u, ", ")
  end

  @spec normalize_multiline_exposing_blocks(String.t()) :: String.t()
  defp normalize_multiline_exposing_blocks(text) when text in ["", nil], do: text || ""

  defp normalize_multiline_exposing_blocks(text) when is_binary(text) do
    text
    |> String.split("\n", trim: false)
    |> normalize_lines_multiline_exposing(0)
    |> Enum.join("\n")
  end

  @spec normalize_lines_multiline_exposing([String.t()], non_neg_integer()) :: [String.t()]
  defp normalize_lines_multiline_exposing(lines, start) do
    case locate_exposing_paren_block_from(lines, start) do
      {open_idx, close_idx} when close_idx > open_idx ->
        if exposing_block_needs_normalize?(lines, open_idx, close_idx) do
          lines
          |> reformat_exposing_block(open_idx, close_idx)
          |> normalize_lines_multiline_exposing(close_idx + 1)
        else
          normalize_lines_multiline_exposing(lines, close_idx + 1)
        end

      :error ->
        lines
    end
  end

  @spec locate_exposing_paren_block_from([String.t()], non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer()} | :error
  defp locate_exposing_paren_block_from(lines, start) do
    with exposing_idx when is_integer(exposing_idx) <-
           lines |> Enum.with_index() |> Enum.drop(start) |> find_exposing_index(),
         open_idx when is_integer(open_idx) <- find_open_paren_line(lines, exposing_idx),
         close_idx when is_integer(close_idx) <- find_close_paren_line(lines, open_idx) do
      {open_idx, close_idx}
    else
      _ -> :error
    end
  end

  @spec find_exposing_index([{String.t(), non_neg_integer()}]) :: non_neg_integer() | nil
  defp find_exposing_index(indexed_lines) do
    Enum.find_value(indexed_lines, fn {line, idx} ->
      if exposing_line?(line), do: idx
    end)
  end

  @spec exposing_block_needs_normalize?([String.t()], non_neg_integer(), non_neg_integer()) ::
          boolean()
  defp exposing_block_needs_normalize?(lines, open_idx, close_idx) do
    open_line = Enum.at(lines, open_idx)
    base_indent = leading_indent(open_line)
    expected_item_indent = base_indent + 2

    lines
    |> Enum.slice((open_idx + 1)..(close_idx - 1)//1)
    |> Enum.any?(fn line ->
      trimmed = String.trim(line)

      cond do
        trimmed == "" -> true
        String.starts_with?(String.trim_leading(line), ",") -> false
        leading_indent(line) != expected_item_indent -> true
        true -> false
      end
    end) or Regex.match?(~r/\(\s{2,}/u, open_line) or Regex.match?(~r/,\s{2,}/u, open_line)
  end

  @spec exposing_line?(String.t()) :: boolean()
  defp exposing_line?(line) when is_binary(line) do
    Regex.match?(~r/\bexposing\b/u, line)
  end

  @spec find_open_paren_line([String.t()], non_neg_integer()) :: non_neg_integer() | nil
  defp find_open_paren_line(lines, start_idx) do
    lines
    |> Enum.with_index()
    |> Enum.drop(start_idx)
    |> Enum.find_value(fn {line, idx} ->
      if String.contains?(strip_comments_for_parens(line), "("), do: idx
    end)
  end

  @spec find_close_paren_line([String.t()], non_neg_integer()) :: non_neg_integer() | nil
  defp find_close_paren_line(lines, open_idx) do
    do_find_close_paren_line(lines, open_idx + 1, 1)
  end

  defp do_find_close_paren_line(_lines, _idx, 0), do: nil

  defp do_find_close_paren_line(lines, idx, depth) when depth > 0 do
    case Enum.at(lines, idx) do
      nil ->
        nil

      line ->
        new_depth = depth + paren_delta(strip_comments_for_parens(line))
        if new_depth == 0, do: idx, else: do_find_close_paren_line(lines, idx + 1, new_depth)
    end
  end

  @spec reformat_exposing_block([String.t()], non_neg_integer(), non_neg_integer()) :: [String.t()]
  defp reformat_exposing_block(lines, open_idx, close_idx) do
    open_line = Enum.at(lines, open_idx)
    base_indent = leading_indent(open_line)
    section_prefix = String.duplicate(" ", base_indent)
    item_prefix = String.duplicate(" ", base_indent + 2)

    open_normalized = normalize_exposing_open_line(open_line, section_prefix)
    close_normalized = section_prefix <> ")"

    inner =
      lines
      |> Enum.slice((open_idx + 1)..(close_idx - 1)//1)
      |> Enum.reject(&(String.trim(&1) == ""))
      |> Enum.map(&normalize_exposing_inner_line(&1, section_prefix, item_prefix))

    Enum.slice(lines, 0, open_idx) ++
      [open_normalized] ++ inner ++ [close_normalized] ++ Enum.drop(lines, close_idx + 1)
  end

  @spec normalize_exposing_open_line(String.t(), String.t()) :: String.t()
  defp normalize_exposing_open_line(line, section_prefix) do
    trimmed = String.trim_leading(line)

    case Regex.run(~r/^\((.*)$/u, trimmed) do
      [_, rest] ->
        section_prefix <> "( " <> normalize_line_whitespace(String.trim_leading(rest))

      _ ->
        section_prefix <> normalize_line_whitespace(trimmed)
    end
  end

  @spec normalize_exposing_inner_line(String.t(), String.t(), String.t()) :: String.t()
  defp normalize_exposing_inner_line(line, section_prefix, item_prefix) do
    trimmed = String.trim_leading(line)

    cond do
      String.starts_with?(trimmed, ",") ->
        section_prefix <> normalize_line_whitespace(trimmed)

      String.starts_with?(trimmed, "--") ->
        if leading_indent(line) > String.length(section_prefix) do
          item_prefix <> trimmed
        else
          section_prefix <> trimmed
        end

      true ->
        item_prefix <> trimmed
    end
  end

  @spec leading_indent(String.t()) :: non_neg_integer()
  defp leading_indent(line) do
    String.length(line) - String.length(String.trim_leading(line))
  end

  @spec strip_comments_for_parens(String.t()) :: String.t()
  defp strip_comments_for_parens(line) do
    line
    |> String.replace(~r/--.*$/u, "")
    |> String.replace(~r/\{-[^}]*-\}/u, "")
  end

  @spec paren_delta(String.t()) :: integer()
  defp paren_delta(line) do
    opens = line |> String.graphemes() |> Enum.count(&(&1 == "("))
    closes = line |> String.graphemes() |> Enum.count(&(&1 == ")"))
    opens - closes
  end
end
