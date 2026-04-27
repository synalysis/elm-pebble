defmodule Ide.Formatter.Semantics.RecordRules do
  @moduledoc false
  alias Ide.Formatter.Semantics.TextOps

  @spec enter_indent(String.t(), non_neg_integer(), non_neg_integer(), String.t(), String.t()) ::
          String.t()
  def enter_indent(current_line, line_start, start_offset, next_char, leading_whitespace)
      when is_binary(current_line) and is_binary(next_char) and is_binary(leading_whitespace) do
    case opening_record_indent(current_line) do
      indent
      when next_char == "," and is_integer(indent) and line_start + indent < start_offset ->
        String.duplicate(" ", indent)

      _ ->
        leading_whitespace
    end
  end

  @spec normalize_multiline_record_alignment(String.t()) :: String.t()
  def normalize_multiline_record_alignment(source) when is_binary(source) do
    source = normalize_record_opening_indentation(source)

    {lines_reversed, _state} =
      source
      |> String.split("\n", trim: false)
      |> Enum.reduce({[], %{indent_stack: [], in_block_comment: false}}, fn line, {acc, state} ->
        next_comment_state = block_comment_state_after(line, state.in_block_comment)

        cond do
          state.in_block_comment ->
            {[line | acc], %{state | in_block_comment: next_comment_state}}

          starts_with_trimmed?(line, "--") ->
            {[line | acc], %{state | in_block_comment: next_comment_state}}

          is_map(opening_record_entry(line)) ->
            entry = opening_record_entry(line)

            {[line | acc],
             %{indent_stack: [entry | state.indent_stack], in_block_comment: next_comment_state}}

          state.indent_stack != [] and starts_with_trimmed?(line, ",") ->
            {normalized_lines, stack_effect} =
              normalize_record_comma_line(line, hd(state.indent_stack).comma_indent)

            next_stack = apply_stack_effect(state.indent_stack, stack_effect)

            {Enum.reverse(normalized_lines) ++ acc,
             %{indent_stack: next_stack, in_block_comment: next_comment_state}}

          state.indent_stack != [] and starts_with_trimmed?(line, "}") ->
            normalized =
              String.duplicate(" ", hd(state.indent_stack).close_indent) <>
                String.trim_leading(line)

            {[normalized | acc],
             %{indent_stack: tl(state.indent_stack), in_block_comment: next_comment_state}}

          true ->
            {[line | acc], %{state | in_block_comment: next_comment_state}}
        end
      end)

    lines_reversed
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  @spec opening_record_indent(String.t()) :: non_neg_integer() | nil
  def opening_record_indent(line) when is_binary(line) do
    trimmed = String.trim_leading(line)
    has_opening? = String.contains?(line, "{")
    has_closing? = String.contains?(line, "}")

    if has_opening? and not has_closing? and not String.starts_with?(trimmed, "{-") do
      case :binary.match(line, "{") do
        {idx, _len} ->
          prefix = String.slice(line, 0, idx) |> String.trim()
          suffix = String.slice(line, idx + 1, String.length(line)) |> String.trim()

          cond do
            prefix == "" and (String.contains?(suffix, ":") or String.contains?(suffix, "=")) ->
              idx

            prefix == "" and starts_with_lower_identifier?(suffix) ->
              idx

            String.ends_with?(prefix, "(") and
                (suffix == "" or String.contains?(suffix, ":") or String.contains?(suffix, "=") or
                   starts_with_lower_identifier?(suffix)) ->
              idx

            String.ends_with?(prefix, "=") and
                (suffix == "" or String.contains?(suffix, ":") or String.contains?(suffix, "=")) ->
              idx

            true ->
              nil
          end

        :nomatch ->
          nil
      end
    else
      nil
    end
  end

  @spec opening_record_entry(term()) :: term()
  defp opening_record_entry(line) do
    case opening_record_indent(line) do
      nil ->
        nil

      indent ->
        if extensible_record_opening?(line) do
          %{
            close_indent: indent,
            # For wrapped openings like "( { model", keep field lines one indent step from
            # the statement indentation rather than from the brace column.
            comma_indent: leading_indent(line) + 4
          }
        else
          %{close_indent: indent, comma_indent: indent}
        end
    end
  end

  @spec normalize_record_comma_line(term(), term()) :: term()
  defp normalize_record_comma_line(line, record_indent) do
    indent = String.duplicate(" ", record_indent)
    trimmed = String.trim_leading(line)

    case split_top_level_close_brace(trimmed) do
      :no_split ->
        normalized_before =
          trimmed
          |> String.trim_trailing()
          |> normalize_record_comma_segment()

        {[indent <> normalized_before], :keep}

      {:split, before, after_part} ->
        comma_line =
          before
          |> String.trim_trailing()
          |> normalize_record_comma_segment()
          |> then(&(indent <> &1))

        closing_line = indent <> "}" <> after_part
        {[comma_line, closing_line], :pop}
    end
  end

  @spec apply_stack_effect(term(), term()) :: term()
  defp apply_stack_effect(indent_stack, :keep), do: indent_stack
  defp apply_stack_effect([], :pop), do: []
  defp apply_stack_effect([_ | rest], :pop), do: rest

  @spec starts_with_lower_identifier?(term()) :: term()
  defp starts_with_lower_identifier?(value) when is_binary(value) do
    trimmed = String.trim_leading(value)

    case String.to_charlist(trimmed) do
      [first | _] -> first in ?a..?z
      _ -> false
    end
  end

  @spec extensible_record_opening?(term()) :: term()
  defp extensible_record_opening?(line) when is_binary(line) do
    case :binary.match(line, "{") do
      {idx, _} ->
        suffix = String.slice(line, idx + 1, String.length(line)) |> String.trim()

        suffix != "" and not String.contains?(suffix, ":") and not String.contains?(suffix, "=") and
          starts_with_lower_identifier?(suffix)

      :nomatch ->
        false
    end
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

  @spec split_top_level_close_brace(term()) :: term()
  defp split_top_level_close_brace(value) when is_binary(value) do
    case top_level_close_brace_index(value, [], false, false, 0) do
      nil ->
        :no_split

      idx ->
        before = binary_part(value, 0, idx)
        after_part = binary_part(value, idx + 1, byte_size(value) - idx - 1)
        {:split, before, after_part}
    end
  end

  @spec top_level_close_brace_index(term(), term(), term(), term(), term()) :: term()
  defp top_level_close_brace_index("", _stack, _in_string, _escape_next, _idx), do: nil

  defp top_level_close_brace_index(
         <<char::utf8, rest::binary>>,
         stack,
         in_string,
         escape_next,
         idx
       ) do
    cond do
      escape_next ->
        top_level_close_brace_index(rest, stack, in_string, false, idx + 1)

      in_string and char == ?\\ ->
        top_level_close_brace_index(rest, stack, in_string, true, idx + 1)

      char == ?" ->
        top_level_close_brace_index(rest, stack, not in_string, false, idx + 1)

      in_string ->
        top_level_close_brace_index(rest, stack, in_string, false, idx + 1)

      char in [?(, ?[, ?{] ->
        top_level_close_brace_index(rest, [char | stack], false, false, idx + 1)

      char in [?), ?], ?}] and stack != [] ->
        top_level_close_brace_index(rest, pop_stack(stack, char), false, false, idx + 1)

      char == ?} and stack == [] ->
        idx

      true ->
        top_level_close_brace_index(rest, stack, false, false, idx + 1)
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

  @spec normalize_record_comma_segment(term()) :: term()
  defp normalize_record_comma_segment(segment) do
    segment
    |> TextOps.normalize_comma_spacing()
    |> normalize_record_field_spacing()
  end

  @spec normalize_record_opening_indentation(term()) :: term()
  defp normalize_record_opening_indentation(source) do
    {normalized_rev, _prev_non_empty} =
      source
      |> String.split("\n", trim: false)
      |> Enum.reduce({[], nil}, fn line, {acc, prev_non_empty} ->
        trimmed = String.trim(line)

        normalized_line =
          if opening_record_candidate?(line, prev_non_empty) do
            expected_indent = prev_non_empty[:indent] + 4
            opening = String.trim_leading(line)
            String.duplicate(" ", expected_indent) <> normalize_record_field_spacing(opening)
          else
            line
          end

        next_prev_non_empty =
          if trimmed == "" do
            prev_non_empty
          else
            %{line: line, trimmed: trimmed, indent: leading_indent(line)}
          end

        {[normalized_line | acc], next_prev_non_empty}
      end)

    normalized_rev
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  @spec opening_record_candidate?(term(), term()) :: term()
  defp opening_record_candidate?(line, prev_non_empty) when is_map(prev_non_empty) do
    trimmed = String.trim_leading(line)

    String.starts_with?(trimmed, "{") and not String.contains?(trimmed, "}") and
      String.contains?(trimmed, ":") and String.ends_with?(prev_non_empty.trimmed, "=")
  end

  defp opening_record_candidate?(_line, _prev_non_empty), do: false

  @spec normalize_record_field_spacing(term()) :: term()
  defp normalize_record_field_spacing(value) do
    value
    |> TextOps.normalize_colon_spacing()
    |> TextOps.collapse_horizontal_runs()
    |> String.trim_trailing()
  end

  @spec starts_with_trimmed?(term(), term()) :: term()
  defp starts_with_trimmed?(line, marker),
    do: String.starts_with?(String.trim_leading(line), marker)

  @spec leading_indent(term()) :: term()
  defp leading_indent(line) do
    String.length(line) - String.length(String.trim_leading(line))
  end
end
