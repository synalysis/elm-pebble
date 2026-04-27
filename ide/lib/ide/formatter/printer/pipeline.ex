defmodule Ide.Formatter.Printer.Pipeline do
  @moduledoc false
  alias Ide.Formatter.Printer.Common.Separators
  alias Ide.Formatter.Printer.Expression
  alias Ide.Formatter.Printer.Expression.Case, as: CasePrinter
  alias Ide.Formatter.Printer.List, as: ListPrinter
  alias Ide.Formatter.Printer.Literal
  alias Ide.Formatter.Printer.ModuleHeader
  alias Ide.Formatter.Printer.Pattern
  alias Ide.Formatter.Printer.Record, as: RecordPrinter
  alias Ide.Formatter.Printer.TopLevel
  alias Ide.Formatter.Printer.TypeDecl
  alias Ide.Formatter.Semantics.Rules

  @spec apply(String.t(), map(), keyword()) :: String.t()
  def apply(source, metadata, opts \\ []) when is_binary(source) and is_map(metadata) do
    source
    |> normalize_legacy_module_syntax()
    |> Pattern.normalize_case_constructor_parens()
    |> Pattern.normalize_nested_as_pattern_parens()
    |> normalize_module_and_import_lines(metadata)
    |> normalize_import_doc_comment_separator()
    |> normalize_single_line_doc_comments()
    |> Literal.normalize_escape_sequences()
    |> ListPrinter.normalize_inline_long_lists()
    |> ListPrinter.normalize_opening_line_items()
    |> ListPrinter.normalize_item_splits(Keyword.get(opts, :tokens))
    |> normalize_definition_rhs_indentation(Keyword.get(opts, :tokens))
    |> Expression.normalize_inline_let_in()
    |> Expression.normalize_inline_if_then_else()
    |> Expression.normalize_multiline_if_alignment()
    |> CasePrinter.normalize_arrow_indentation()
    |> Expression.normalize_range_expressions()
    |> Expression.normalize_multiline_tuple_alignment()
    |> Expression.normalize_record_tuple_comma_pair()
    |> Separators.normalize_commas(Keyword.get(opts, :tokens))
    |> RecordPrinter.normalize()
    |> ListPrinter.normalize_opening_indentation(Keyword.get(opts, :tokens))
    |> ListPrinter.normalize_closing_bracket_lines()
    |> ListPrinter.normalize_alignment(Keyword.get(opts, :tokens))
    |> Expression.normalize_nested_call_list_arguments()
    |> Expression.normalize_multiline_nested_call_list_arguments()
    |> Expression.normalize_multiline_call_argument_alignment()
    |> ListPrinter.normalize_closing_bracket_lines()
    |> ListPrinter.normalize_alignment(Keyword.get(opts, :tokens))
    |> TypeDecl.normalize_alias_head_spacing()
    |> TypeDecl.normalize_union_constructor_alignment()
    |> normalize_top_level_declaration_spacing()
    |> Expression.normalize_multiline_nested_call_block_indentation()
  end

  @spec normalize_legacy_module_syntax(term()) :: term()
  defp normalize_legacy_module_syntax(source) do
    source
    |> String.split("\n", trim: false)
    |> Enum.map(&normalize_legacy_module_line/1)
    |> Enum.join("\n")
  end

  @spec normalize_module_and_import_lines(term(), term()) :: term()
  defp normalize_module_and_import_lines(source, metadata) do
    ModuleHeader.normalize(source, metadata)
  end

  @spec normalize_legacy_module_line(term()) :: term()
  defp normalize_legacy_module_line(line) do
    trimmed = String.trim(line)

    if String.ends_with?(trimmed, " where") and String.contains?(trimmed, "module ") and
         String.contains?(trimmed, "(") and String.contains?(trimmed, ")") do
      indent = leading_spaces(line)
      body = String.trim_leading(line)
      before_where = String.trim_trailing(String.slice(body, 0, String.length(body) - 6))

      case split_once(before_where, "(") do
        {prefix, rest} ->
          case split_once(rest, ")") do
            {inside, after_paren} ->
              if String.trim(after_paren) == "" do
                indent <>
                  String.trim_trailing(prefix) <> " exposing (" <> String.trim(inside) <> ")"
              else
                line
              end

            :error ->
              line
          end

        :error ->
          line
      end
    else
      line
    end
  end

  @spec split_once(term(), term()) :: term()
  defp split_once(value, delimiter) do
    case :binary.match(value, delimiter) do
      {idx, len} ->
        {
          binary_part(value, 0, idx),
          binary_part(value, idx + len, byte_size(value) - idx - len)
        }

      :nomatch ->
        :error
    end
  end

  @spec normalize_definition_rhs_indentation(term(), term()) :: term()
  defp normalize_definition_rhs_indentation(source, _tokens) when is_binary(source) do
    {normalized_rev, _pending, _in_block_comment} =
      source
      |> String.split("\n", trim: false)
      |> Enum.reduce({[], nil, false}, fn line, {acc, pending, in_block_comment} ->
        trimmed = String.trim(line)
        indent = leading_indent(line)
        next_in_block_comment = block_comment_state_after(line, in_block_comment)

        cond do
          in_block_comment ->
            {[line | acc], pending, next_in_block_comment}

          is_integer(pending) and trimmed == "" ->
            {[line | acc], pending, next_in_block_comment}

          is_integer(pending) and
              (starts_with_trimmed?(line, ",") or starts_with_trimmed?(line, "|") or
                 starts_with_trimmed?(line, "]") or starts_with_trimmed?(line, "}") or
                 starts_with_trimmed?(line, ")")) ->
            {[line | acc], nil, next_in_block_comment}

          is_integer(pending) and starts_with_trimmed?(line, "--") ->
            normalized = String.duplicate(" ", pending) <> String.trim_leading(line)
            {[normalized | acc], pending, next_in_block_comment}

          is_integer(pending) and trimmed != "" ->
            normalized = String.duplicate(" ", pending) <> String.trim_leading(line)
            {[normalized | acc], nil, next_in_block_comment}

          rhs_anchor_line?(line) ->
            {[line | acc], indent + Rules.indent_width(), next_in_block_comment}

          true ->
            {[line | acc], nil, next_in_block_comment}
        end
      end)

    normalized_rev
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  @spec block_comment_state_after(term(), term()) :: term()
  defp block_comment_state_after(line, in_block_comment) do
    trimmed = String.trim_leading(line)
    opens? = String.contains?(trimmed, "{-")
    closes? = String.contains?(trimmed, "-}")

    cond do
      in_block_comment and closes? and not opens? -> false
      in_block_comment -> true
      opens? and not closes? -> true
      true -> false
    end
  end

  @spec rhs_anchor_line?(term()) :: term()
  defp rhs_anchor_line?(line) do
    trimmed = String.trim_leading(line)
    indent = leading_indent(line)

    cond do
      trimmed == "" ->
        false

      rem(indent, Rules.indent_width()) != 0 ->
        false

      starts_with_trimmed?(line, "--") or starts_with_trimmed?(line, "{-") ->
        false

      String.starts_with?(trimmed, "let ") or String.starts_with?(trimmed, "in ") ->
        false

      String.starts_with?(trimmed, "type ") or String.starts_with?(trimmed, "import ") or
        String.starts_with?(trimmed, "module ") or String.starts_with?(trimmed, "port ") or
        String.starts_with?(trimmed, "infix ") or String.starts_with?(trimmed, "infixl ") or
          String.starts_with?(trimmed, "infixr ") ->
        false

      true ->
        case split_top_level_once(trimmed, "=") do
          {lhs, _rhs} ->
            lhs = String.trim_trailing(lhs)
            lhs != "" and definition_lhs_candidate?(lhs)

          :error ->
            false
        end
    end
  end

  @spec split_top_level_once(term(), term()) :: term()
  defp split_top_level_once(value, delimiter) when is_binary(value) and delimiter == "=" do
    case top_level_delimiter_index(value, ?=) do
      nil ->
        :error

      idx ->
        {
          binary_part(value, 0, idx),
          binary_part(value, idx + 1, byte_size(value) - idx - 1)
        }
    end
  end

  @spec top_level_delimiter_index(term(), term()) :: term()
  defp top_level_delimiter_index(value, delimiter_char) do
    do_top_level_delimiter_index(value, delimiter_char, [], false, false, 0)
  end

  @spec do_top_level_delimiter_index(term(), term(), term(), term(), term(), term()) :: term()
  defp do_top_level_delimiter_index("", _delimiter_char, _stack, _in_string, _escape_next, _idx),
    do: nil

  defp do_top_level_delimiter_index(
         <<char::utf8, rest::binary>>,
         delimiter_char,
         stack,
         in_string,
         escape_next,
         idx
       ) do
    cond do
      escape_next ->
        do_top_level_delimiter_index(rest, delimiter_char, stack, in_string, false, idx + 1)

      in_string and char == ?\\ ->
        do_top_level_delimiter_index(rest, delimiter_char, stack, in_string, true, idx + 1)

      char == ?" ->
        do_top_level_delimiter_index(rest, delimiter_char, stack, not in_string, false, idx + 1)

      in_string ->
        do_top_level_delimiter_index(rest, delimiter_char, stack, in_string, false, idx + 1)

      char in [?(, ?[, ?{] ->
        do_top_level_delimiter_index(rest, delimiter_char, [char | stack], false, false, idx + 1)

      char in [?), ?], ?}] ->
        do_top_level_delimiter_index(
          rest,
          delimiter_char,
          pop_stack(stack, char),
          false,
          false,
          idx + 1
        )

      stack == [] and char == delimiter_char ->
        idx

      true ->
        do_top_level_delimiter_index(rest, delimiter_char, stack, false, false, idx + 1)
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

  @spec definition_lhs_candidate?(term()) :: term()
  defp definition_lhs_candidate?(lhs) when is_binary(lhs) do
    chars = String.to_charlist(lhs)

    case chars do
      [first | _] ->
        first in ?a..?z or first == ?_ or first == ?(

      _ ->
        false
    end
  end

  @spec leading_indent(term()) :: term()
  defp leading_indent(line) do
    String.length(line) - String.length(String.trim_leading(line))
  end

  @spec leading_spaces(term()) :: term()
  defp leading_spaces(line) do
    String.slice(line, 0, leading_indent(line))
  end

  @spec starts_with_trimmed?(term(), term()) :: term()
  defp starts_with_trimmed?(line, marker) when is_binary(marker) do
    String.trim_leading(line) |> String.starts_with?(marker)
  end

  @spec normalize_top_level_declaration_spacing(term()) :: term()
  defp normalize_top_level_declaration_spacing(source) do
    TopLevel.normalize(source)
  end

  @spec normalize_single_line_doc_comments(term()) :: term()
  defp normalize_single_line_doc_comments(source) do
    source
    |> String.split("\n", trim: false)
    |> Enum.map(&expand_single_line_doc_comment/1)
    |> List.flatten()
    |> Enum.join("\n")
  end

  @spec expand_single_line_doc_comment(term()) :: term()
  defp expand_single_line_doc_comment(line) do
    trimmed = String.trim_leading(line)
    indent = leading_spaces(line)

    if String.starts_with?(trimmed, "{-|") and String.ends_with?(trimmed, "-}") and
         not String.contains?(trimmed, "\n") do
      content =
        trimmed
        |> String.trim_leading("{-|")
        |> String.trim_trailing("-}")
        |> String.trim()

      if content == "" do
        [line]
      else
        [indent <> "{-| " <> content, indent <> "-}"]
      end
    else
      [line]
    end
  end

  @spec normalize_import_doc_comment_separator(term()) :: term()
  defp normalize_import_doc_comment_separator(source) do
    source
    |> String.split("\n", trim: false)
    |> Enum.reduce([], fn line, acc ->
      trimmed = String.trim_leading(line)
      at_top_level = leading_indent(line) == 0

      if at_top_level and String.starts_with?(trimmed, "{-|") do
        case last_non_empty_line(acc) do
          nil ->
            acc ++ [line]

          prev ->
            if String.starts_with?(String.trim_leading(prev), "import ") do
              if List.last(acc) == "" do
                acc ++ [line]
              else
                acc ++ ["", line]
              end
            else
              acc ++ [line]
            end
        end
      else
        acc ++ [line]
      end
    end)
    |> Enum.join("\n")
  end

  @spec last_non_empty_line(term()) :: term()
  defp last_non_empty_line(lines) when is_list(lines) do
    lines
    |> Enum.reverse()
    |> Enum.find(fn line -> String.trim(line) != "" end)
  end
end
