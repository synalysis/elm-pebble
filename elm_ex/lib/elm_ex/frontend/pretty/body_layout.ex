defmodule ElmEx.Frontend.Pretty.BodyLayout do
  @moduledoc false

  alias ElmEx.Frontend.Layout
  alias ElmEx.Frontend.Pretty.Literal

  @spec normalize_function_body(String.t()) :: String.t()
  def normalize_function_body(body) when is_binary(body) do
    body
    |> String.split("\n", trim: false)
    |> deepen_multiline_case_arrows()
    |> Enum.join("\n")
    |> normalize_case_pattern_parens_in_body()
    |> desugar_list_range()
    |> normalize_body_literals()
    |> String.trim_leading("\n")
    |> String.trim_trailing()
  end

  @spec normalize_body_literals(String.t()) :: String.t()
  defp normalize_body_literals(body) do
    body
    |> String.split("\n", trim: false)
    |> normalize_literal_lines([])
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  @spec normalize_literal_lines([String.t()], [String.t()]) :: [String.t()]
  defp normalize_literal_lines([], acc), do: acc

  defp normalize_literal_lines([line | rest], acc) do
    if multiline_triple_block_start?(line) do
      {block_lines, remaining} = take_multiline_triple_block([line | rest])
      normalized = block_lines |> Enum.join("\n") |> normalize_triple_quoted_block()
      normalize_literal_lines(remaining, [normalized | acc])
    else
      normalize_literal_lines(rest, [normalize_plain_line(line) | acc])
    end
  end

  @spec multiline_triple_block_start?(String.t()) :: boolean()
  defp multiline_triple_block_start?(line) do
    case :binary.match(line, "\"\"\"") do
      {start, 3} -> not same_line_triple_closed?(String.slice(line, start + 3, byte_size(line)))
      _ -> false
    end
  end

  @spec same_line_triple_closed?(String.t()) :: boolean()
  defp same_line_triple_closed?(after_open) do
    find_unescaped_triple_close(after_open) != nil
  end

  @spec take_multiline_triple_block([String.t()]) :: {[String.t()], [String.t()]}
  defp take_multiline_triple_block([line | rest]) do
    if multiline_triple_block_end?(line) do
      {[line], rest}
    else
      {more, remaining} = take_multiline_triple_block(rest)
      {[line | more], remaining}
    end
  end

  defp take_multiline_triple_block([]), do: {[], []}

  @spec multiline_triple_block_end?(String.t()) :: boolean()
  defp multiline_triple_block_end?(line) do
    String.trim(line) == "\"\"\""
  end

  @spec normalize_triple_quoted_block(String.t()) :: String.t()
  defp normalize_triple_quoted_block(text) do
    text
    |> normalize_hex_escapes_text()
    |> normalize_special_whitespace_text()
  end

  @spec normalize_plain_line(String.t()) :: String.t()
  defp normalize_plain_line(line) do
    line
    |> normalize_same_line_triple_strings()
    |> normalize_special_string_literals()
    |> normalize_char_literals()
  end

  @spec normalize_same_line_triple_strings(String.t()) :: String.t()
  defp normalize_same_line_triple_strings(line) do
    case :binary.match(line, "\"\"\"") do
      :nomatch ->
        line

      {start, 3} ->
        prefix = String.slice(line, 0, start)
        rest = String.slice(line, start + 3, byte_size(line) - start - 3)

        case find_unescaped_triple_close(rest) do
          nil ->
            line

          close_idx ->
            middle = String.slice(rest, 0, close_idx)
            suffix_start = start + 3 + close_idx + 3
            suffix = String.slice(line, suffix_start, byte_size(line) - suffix_start)

            prefix <>
              "\"\"\"" <>
              (middle |> normalize_hex_escapes_text() |> normalize_special_whitespace_text()) <>
              "\"\"\"" <> normalize_same_line_triple_strings(suffix)
        end
    end
  end

  @spec normalize_special_whitespace_text(String.t()) :: String.t()
  defp normalize_special_whitespace_text(text) do
    text
    |> String.replace(<<0xA0::utf8>>, "\\u{00A0}")
    |> String.replace(<<0x2000::utf8>>, "\\u{2000}")
    |> String.replace(<<0x205F::utf8>>, "\\u{205F}")
  end

  @spec find_unescaped_triple_close(String.t()) :: non_neg_integer() | nil
  defp find_unescaped_triple_close(string) do
    find_unescaped_triple_close(string, 0, byte_size(string))
  end

  defp find_unescaped_triple_close(_string, idx, len) when idx + 2 >= len, do: nil

  defp find_unescaped_triple_close(string, idx, len) do
    if String.slice(string, idx, 3) == "\"\"\"" and not escaped_at?(string, idx) do
      idx
    else
      find_unescaped_triple_close(string, idx + 1, len)
    end
  end

  @spec escaped_at?(String.t(), non_neg_integer()) :: boolean()
  defp escaped_at?(string, idx) when idx > 0 do
    String.at(string, idx - 1) == "\\"
  end

  defp escaped_at?(_string, 0), do: false

  @spec normalize_hex_escapes_text(String.t()) :: String.t()
  defp normalize_hex_escapes_text(text) do
    Regex.replace(~r/\\x([0-9A-Fa-f]+)/u, text, fn _match, hex ->
      hex
      |> String.to_integer(16)
      |> Literal.unicode_escape()
    end)
  end

  @spec normalize_special_string_literals(String.t()) :: String.t()
  defp normalize_special_string_literals(body) do
    Regex.replace(~r/"([^"\\]|\\.)*"/u, body, fn string ->
      inner = String.slice(string, 1..-2//1)

      if special_string_literal?(inner) do
        "\"#{inner |> decode_string_literal() |> Literal.escape_string()}\""
      else
        string
      end
    end)
  end

  defp special_string_literal?(inner) do
    String.contains?(inner, "\\x") or String.contains?(inner, [<<0xA0::utf8>>])
  end

  defp decode_string_literal(inner) do
    Regex.replace(~r/\\x([0-9A-Fa-f]+)/u, inner, fn _, hex ->
      <<String.to_integer(hex, 16)::utf8>>
    end)
  end

  @spec normalize_char_literals(String.t()) :: String.t()
  defp normalize_char_literals(body) do
    Regex.replace(~r/'([^'\\]|\\.)*'/u, body, fn char ->
      inner = String.slice(char, 1..-2//1)

      if special_char_literal?(inner) do
        "'#{inner |> decode_char_literal() |> Literal.escape_string()}'"
      else
        char
      end
    end)
  end

  defp special_char_literal?(inner) do
    String.contains?(inner, "\\x") or
      inner
      |> decode_char_literal()
      |> String.to_charlist()
      |> Enum.any?(fn cp -> cp in [0xA0, 0x2000, 0x205F] end)
  end

  defp decode_char_literal(inner) do
    inner
    |> String.replace("\\n", "\n")
    |> String.replace("\\t", "\t")
    |> String.replace("\\'", "'")
    |> String.replace("\\\\", "\\")
    |> decode_string_literal()
  end

  @spec desugar_list_range(String.t()) :: String.t()
  defp desugar_list_range(body) do
    Regex.replace(~r/\[\s*(-?\d+)\s*\.\.\s*(-?\d+)\s*\]/u, body, "List.range \\1 \\2")
  end

  @spec normalize_case_pattern_parens_in_body(String.t()) :: String.t()
  defp normalize_case_pattern_parens_in_body(body) when is_binary(body) do
    body
    |> String.split("\n", trim: false)
    |> Enum.map(&normalize_case_pattern_parens_line/1)
    |> Enum.join("\n")
  end

  @spec normalize_case_pattern_parens_line(String.t()) :: String.t()
  defp normalize_case_pattern_parens_line(line) when is_binary(line) do
    if Regex.match?(~r/\s->\s*$/u, String.trim_trailing(line)) do
      line
      |> then(
        &Regex.replace(
          ~r/\(\(([A-Z][\w'.]*(?:\.[A-Z][\w']*)*)\)\s+as\s+([a-z][\w']*)\)/u,
          &1,
          "(\\1 as \\2)"
        )
      )
      |> then(
        &Regex.replace(
          ~r/\s+\(([A-Z][\w'.]*\.[A-Z][\w']*)\)(?!\s+as)/u,
          &1,
          " \\1"
        )
      )
    else
      line
    end
  end

  @spec deepen_multiline_case_arrows([String.t()]) :: [String.t()]
  defp deepen_multiline_case_arrows(lines) do
    deepen_marks = build_case_arrow_deepen_marks(lines)

    lines
    |> Enum.with_index()
    |> Enum.map(fn {line, idx} ->
      if MapSet.member?(deepen_marks, idx) do
        deepen_line(line, Layout.indent_step())
      else
        line
      end
    end)
  end

  @spec build_case_arrow_deepen_marks([String.t()]) :: MapSet.t()
  defp build_case_arrow_deepen_marks(lines) do
    Enum.reduce(0..(length(lines) - 1), MapSet.new(), fn idx, acc ->
      line = Enum.at(lines, idx)

      if case_arrow_line?(line) and deepen_case_arrow?(lines, idx) do
        arrow_indent = leading_indent(line)
        body_end = find_case_branch_body_end(lines, idx, arrow_indent)

        acc
        |> MapSet.put(idx)
        |> then(fn marked ->
          Enum.reduce((idx + 1)..body_end, marked, fn body_idx, body_acc ->
            body_line = Enum.at(lines, body_idx)

            if String.trim(body_line) == "" do
              body_acc
            else
              MapSet.put(body_acc, body_idx)
            end
          end)
        end)
      else
        acc
      end
    end)
  end

  @spec find_case_branch_body_end([String.t()], non_neg_integer(), non_neg_integer()) ::
          non_neg_integer()
  defp find_case_branch_body_end(lines, arrow_idx, arrow_indent) do
    lines
    |> Enum.drop(arrow_idx + 1)
    |> Enum.with_index(arrow_idx + 1)
    |> Enum.find_value(fn {line, idx} ->
      indent = leading_indent(line)
      trimmed = String.trim(line)

      if trimmed != "" and indent <= arrow_indent, do: idx - 1
    end)
    |> case do
      nil -> length(lines) - 1
      end_idx -> end_idx
    end
  end

  @spec case_arrow_line?(String.t()) :: boolean()
  defp case_arrow_line?(line) do
    String.trim(line) == "->"
  end

  @spec deepen_case_arrow?([String.t()], non_neg_integer()) :: boolean()
  defp deepen_case_arrow?(lines, arrow_idx) do
    arrow_indent = leading_indent(Enum.at(lines, arrow_idx, ""))

    pattern_lines =
      lines
      |> Enum.take(arrow_idx)
      |> Enum.reverse()
      |> Enum.reduce_while([], fn line, acc ->
        indent = leading_indent(line)
        trimmed = String.trim(line)

        cond do
          trimmed == "" ->
            {:cont, acc}

          indent < arrow_indent ->
            {:halt, acc}

          indent > arrow_indent ->
            {:halt, acc}

          case_arrow_line?(line) ->
            {:halt, acc}

          true ->
            {:cont, [line | acc]}
        end
      end)

    length(pattern_lines) > 1 or Enum.any?(pattern_lines, &comment_line?/1)
  end

  @spec comment_line?(String.t()) :: boolean()
  defp comment_line?(line) do
    trimmed = String.trim_leading(line)

    String.starts_with?(trimmed, "--") or
      (String.starts_with?(trimmed, "{-") and String.ends_with?(trimmed, "-}"))
  end

  @spec deepen_line(String.t(), pos_integer()) :: String.t()
  defp deepen_line(line, extra_spaces) when is_integer(extra_spaces) and extra_spaces >= 0 do
    String.duplicate(" ", leading_indent(line) + extra_spaces) <> String.trim_leading(line)
  end

  @spec leading_indent(String.t()) :: non_neg_integer()
  defp leading_indent(line) do
    String.length(line) - String.length(String.trim_leading(line))
  end
end
