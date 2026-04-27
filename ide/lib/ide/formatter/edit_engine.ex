defmodule Ide.Formatter.EditEngine do
  @moduledoc false
  alias Ide.Formatter.Printer.TypeDecl
  alias Ide.Formatter.Semantics.RecordRules
  alias Ide.Formatter.Semantics.Rules
  alias Ide.Formatter.Semantics.SpacingRules

  @type edit_result :: %{
          next_content: String.t(),
          cursor_start: non_neg_integer(),
          cursor_end: non_neg_integer()
        }

  @spec compute_tab_edit(String.t(), non_neg_integer(), non_neg_integer(), boolean()) ::
          edit_result()
  def compute_tab_edit(content, start_offset, end_offset, outdent?)
      when is_binary(content) and is_integer(start_offset) and is_integer(end_offset) do
    start_offset = clamp_offset(content, start_offset)
    end_offset = clamp_offset(content, end_offset)
    has_selection = end_offset > start_offset
    line_start = current_line_start(content, start_offset)
    block_end = selection_block_end(content, end_offset)

    if has_selection do
      apply_block_indent_edit(content, line_start, start_offset, end_offset, block_end, outdent?)
    else
      apply_single_indent_edit(content, line_start, start_offset, outdent?)
    end
  end

  @spec compute_enter_edit(String.t(), non_neg_integer(), non_neg_integer()) :: edit_result()
  def compute_enter_edit(content, start_offset, end_offset)
      when is_binary(content) and is_integer(start_offset) and is_integer(end_offset) do
    start_offset = clamp_offset(content, start_offset)
    end_offset = clamp_offset(content, end_offset)
    line_start = current_line_start(content, start_offset)
    line_end = current_line_end(content, start_offset)
    current_line = slice_range(content, line_start, line_end)
    prefix = slice_range(content, line_start, start_offset)
    leading_whitespace = leading_whitespace(prefix)

    cursor_in_line = start_offset - line_start

    case type_equals_split_edit(current_line, cursor_in_line, leading_whitespace) do
      {:ok, replacement, next_col} ->
        patched_content =
          slice_range(content, 0, line_start) <>
            replacement <> slice_range(content, line_end, String.length(content))

        patched_pos = line_start + next_col

        {next_content, next_pos} =
          normalize_union_alignment_for_enter(patched_content, patched_pos)

        %{next_content: next_content, cursor_start: next_pos, cursor_end: next_pos}

      :error ->
        next_char = char_at(content, start_offset)

        indent =
          if SpacingRules.comma_char?(next_char) do
            RecordRules.enter_indent(
              current_line,
              line_start,
              start_offset,
              next_char,
              leading_whitespace
            )
          else
            enter_indent(leading_whitespace, current_line, prefix, start_offset, line_end)
          end

        patched_content =
          slice_range(content, 0, start_offset) <>
            "\n" <> indent <> slice_range(content, end_offset, String.length(content))

        patched_pos = start_offset + 1 + String.length(indent)

        {next_content, next_pos} =
          normalize_union_alignment_for_enter(patched_content, patched_pos)

        %{next_content: next_content, cursor_start: next_pos, cursor_end: next_pos}
    end
  end

  @spec apply_single_indent_edit(term(), term(), term(), term()) :: term()
  defp apply_single_indent_edit(content, line_start, start_offset, outdent?) do
    if outdent? do
      before_cursor = slice_range(content, line_start, start_offset)
      leading_spaces = String.length((Regex.run(~r/^ */, before_cursor) || [""]) |> hd())
      indent_width = Rules.indent_width()
      removable = min(indent_width, min(leading_spaces, start_offset - line_start))

      next_content =
        slice_range(content, 0, start_offset - removable) <>
          slice_range(content, start_offset, String.length(content))

      next_pos = start_offset - removable
      %{next_content: next_content, cursor_start: next_pos, cursor_end: next_pos}
    else
      column = start_offset - line_start
      indent_width = Rules.indent_width()
      remainder = rem(column, indent_width)
      spaces = if remainder == 0, do: indent_width, else: indent_width - remainder
      indent = String.duplicate(" ", spaces)

      next_content =
        slice_range(content, 0, start_offset) <>
          indent <> slice_range(content, start_offset, String.length(content))

      next_pos = start_offset + spaces
      %{next_content: next_content, cursor_start: next_pos, cursor_end: next_pos}
    end
  end

  @spec apply_block_indent_edit(term(), term(), term(), term(), term(), term()) :: term()
  defp apply_block_indent_edit(content, line_start, start_offset, end_offset, block_end, outdent?) do
    block = slice_range(content, line_start, block_end)
    lines = String.split(block, "\n")

    transformed_lines =
      if outdent? do
        indent_width = Rules.indent_width()
        Enum.map(lines, &String.replace(&1, ~r/^ {1,#{indent_width}}/, ""))
      else
        indent = String.duplicate(" ", Rules.indent_width())
        Enum.map(lines, &(indent <> &1))
      end

    replaced = Enum.join(transformed_lines, "\n")

    next_content =
      slice_range(content, 0, line_start) <>
        replaced <> slice_range(content, block_end, String.length(content))

    new_start =
      if outdent? do
        indent_width = Rules.indent_width()
        max(line_start, start_offset - min(indent_width, start_offset - line_start))
      else
        start_offset + Rules.indent_width()
      end

    delta = String.length(replaced) - String.length(block)
    new_end = end_offset + delta

    %{next_content: next_content, cursor_start: new_start, cursor_end: new_end}
  end

  @spec clamp_offset(term(), term()) :: term()
  defp clamp_offset(content, offset) do
    max(0, min(offset, String.length(content)))
  end

  @spec current_line_start(term(), term()) :: term()
  defp current_line_start(content, offset) do
    prefix = slice_range(content, 0, offset)

    case :binary.matches(prefix, "\n") do
      [] ->
        0

      matches ->
        {idx, _len} = List.last(matches)
        idx + 1
    end
  end

  @spec current_line_end(term(), term()) :: term()
  defp current_line_end(content, offset) do
    case :binary.match(slice_range(content, offset, String.length(content)), "\n") do
      :nomatch -> String.length(content)
      {rel, _len} -> offset + rel
    end
  end

  @spec selection_block_end(term(), term()) :: term()
  defp selection_block_end(content, end_offset) do
    case :binary.match(slice_range(content, end_offset, String.length(content)), "\n") do
      :nomatch -> String.length(content)
      {rel, _len} -> end_offset + rel
    end
  end

  @spec char_at(term(), term()) :: term()
  defp char_at(content, offset) do
    String.at(content, offset) || ""
  end

  @spec leading_whitespace(term()) :: term()
  defp leading_whitespace(value) do
    (Regex.run(~r/^[ \t]*/, value) || [""]) |> hd()
  end

  @spec enter_indent(term(), term(), term(), term(), term()) :: term()
  defp enter_indent(base_indent, current_line, prefix, start_offset, line_end) do
    next_char = char_at(current_line, String.length(prefix))
    trimmed_prefix = String.trim_trailing(prefix)
    trimmed_line = String.trim(current_line)

    type_equals_split? =
      next_char == "=" and
        type_declaration_head_line?(trimmed_prefix) and
        String.contains?(trimmed_line, "=")

    should_increase? =
      type_equals_split? or
        (line_tail_blank?(prefix, start_offset, line_end) and
           continuation_indent_trigger?(current_line, prefix))

    if should_increase? do
      base_indent <> String.duplicate(" ", Rules.indent_width())
    else
      base_indent
    end
  end

  @spec type_equals_split_edit(term(), term(), term()) :: term()
  defp type_equals_split_edit(current_line, cursor_in_line, leading_whitespace) do
    case :binary.match(current_line, "=") do
      {eq_index, 1} ->
        head = String.slice(current_line, 0, eq_index)
        head_trimmed = String.trim_trailing(head)

        rhs =
          String.slice(current_line, eq_index, String.length(current_line) - eq_index)
          |> String.trim_leading()

        cursor_near_equals? = cursor_in_line >= eq_index and cursor_in_line <= eq_index + 1
        type_head? = type_declaration_head_line?(String.trim_leading(head_trimmed))
        has_rhs? = rhs != ""

        if cursor_near_equals? and type_head? and has_rhs? do
          indent = leading_whitespace <> String.duplicate(" ", Rules.indent_width())
          replacement = head_trimmed <> "\n" <> indent <> rhs
          next_col = String.length(head_trimmed) + 1 + String.length(indent)
          {:ok, replacement, next_col}
        else
          :error
        end

      :nomatch ->
        :error
    end
  end

  @spec line_tail_blank?(term(), term(), term()) :: term()
  defp line_tail_blank?(prefix, start_offset, line_end)
       when is_integer(start_offset) and is_integer(line_end) do
    _ = prefix
    start_offset >= line_end
  end

  @spec continuation_indent_trigger?(term(), term()) :: term()
  defp continuation_indent_trigger?(current_line, prefix) do
    trimmed_prefix = String.trim_trailing(prefix)
    trimmed_line = String.trim(current_line)

    String.ends_with?(trimmed_prefix, "=") or
      String.ends_with?(trimmed_prefix, "->") or
      Regex.match?(~r/\b(?:of|let|then|else|where)\s*$/, trimmed_prefix) or
      type_declaration_head_line?(trimmed_line)
  end

  @spec type_declaration_head_line?(term()) :: term()
  defp type_declaration_head_line?(line) when is_binary(line) do
    starts_type? = String.starts_with?(line, "type ")
    starts_alias? = String.starts_with?(line, "type alias ")
    starts_type? and not starts_alias?
  end

  @spec normalize_union_alignment_for_enter(term(), term()) :: term()
  defp normalize_union_alignment_for_enter(content, cursor_offset) do
    if Regex.match?(~r/^\s*[=|]\s/m, content) do
      {line, col} = offset_to_line_col(content, cursor_offset)
      normalized = TypeDecl.normalize_union_constructor_alignment(content)

      if normalized == content do
        {content, cursor_offset}
      else
        {normalized, line_col_to_offset(normalized, line, col)}
      end
    else
      {content, cursor_offset}
    end
  end

  @spec offset_to_line_col(term(), term()) :: term()
  defp offset_to_line_col(content, offset) do
    safe_offset = clamp_offset(content, offset)
    prefix = slice_range(content, 0, safe_offset)
    parts = String.split(prefix, "\n", trim: false)
    line = max(length(parts), 1)
    col = String.length(List.last(parts) || "")
    {line, col}
  end

  @spec line_col_to_offset(term(), term(), term()) :: term()
  defp line_col_to_offset(content, line, col) do
    lines = String.split(content, "\n", trim: false)
    safe_line = max(1, min(line, length(lines)))
    safe_col = max(0, col)
    before_lines = Enum.take(lines, safe_line - 1)
    line_text = Enum.at(lines, safe_line - 1) || ""

    line_prefix_len =
      Enum.reduce(before_lines, 0, fn row, acc -> acc + String.length(row) + 1 end)

    line_prefix_len + min(safe_col, String.length(line_text))
  end

  @spec slice_range(term(), term(), term()) :: term()
  defp slice_range(content, from, to) when from <= to do
    String.slice(content, from, to - from)
  end
end
