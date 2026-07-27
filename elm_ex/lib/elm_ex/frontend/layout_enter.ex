defmodule ElmEx.Frontend.LayoutEnter do
  @moduledoc """
  Indentation for Enter and Tab in the editor.

  Reuses the same block/indent stack semantics as `ExprLayoutLexer` and the
  binding/arm heuristics from `LayoutRules`, so editor behavior matches parse
  and print layout.
  """

  alias ElmEx.Frontend.{ExprLayoutLexer, Layout}

  @type block_kind :: :let | :case
  @type cont_kind :: nil | :after_eq | :after_arrow
  @type state :: %{
          indent_stack: [non_neg_integer()],
          blocks: [block_kind()],
          cont: cont_kind()
        }

  @doc """
  Whitespace prefix for the line created by pressing Enter at `offset`.
  """
  @spec indent_string(String.t(), non_neg_integer()) :: String.t()
  def indent_string(source, offset) when is_binary(source) do
    source
    |> indent_column(offset)
    |> then(&String.duplicate(" ", &1))
  end

  @doc """
  Physical column (number of leading spaces) for the line after Enter.
  """
  @spec indent_column(String.t(), non_neg_integer()) :: non_neg_integer()
  def indent_column(source, offset) when is_binary(source) do
    offset = clamp_offset(source, offset)
    line_start = line_start_at(source, offset)
    line_end = line_end_at(source, offset)
    prefix = String.slice(source, line_start, offset - line_start)
    leading = leading_whitespace(prefix)
    base_column = String.length(leading)
    at_line_end = offset >= line_end
    trimmed_prefix = String.trim_trailing(prefix)
    trimmed_line = String.trim(String.slice(source, line_start, line_end - line_start))

    state = layout_state_before(source, line_start)

    cond do
      at_line_end and type_declaration_head?(trimmed_line) ->
        base_column + Layout.indent_step()

      at_line_end and increase_after_block_keyword?(trimmed_prefix) ->
        base_column + Layout.indent_step()

      at_line_end and String.ends_with?(trimmed_prefix, "->") ->
        base_column + Layout.indent_step()

      at_line_end and String.ends_with?(trimmed_prefix, "=") ->
        base_column + Layout.indent_step()

      :let in state.blocks ->
        block_indent_column(state, base_column)

      :case in state.blocks ->
        block_indent_column(state, base_column)

      true ->
        base_column
    end
  end

  @doc """
  Spaces to insert when Tab is pressed at `offset` (no selection).

  On a whitespace-only line prefix, snaps toward the layout column for that line.
  Otherwise advances to the next indent stop within the line.
  """
  @spec tab_insert_string(String.t(), non_neg_integer()) :: String.t()
  def tab_insert_string(source, offset) when is_binary(source) do
    offset = clamp_offset(source, offset)
    line_start = line_start_at(source, offset)
    prefix = String.slice(source, line_start, offset - line_start)
    step = Layout.indent_step()

    if Regex.match?(~r/^[ \t]*$/, prefix) do
      target = indent_column(source, offset)
      current = String.length(prefix)

      if target > current do
        String.duplicate(" ", target - current)
      else
        pad_to_next_stop(offset - line_start, step)
      end
    else
      pad_to_next_stop(offset - line_start, step)
    end
  end

  @spec pad_to_next_stop(non_neg_integer(), pos_integer()) :: String.t()
  defp pad_to_next_stop(column, step) do
    remainder = rem(column, step)
    spaces = if remainder == 0, do: step, else: step - remainder
    String.duplicate(" ", spaces)
  end

  @spec layout_state_before(String.t(), non_neg_integer()) :: state()
  defp layout_state_before(source, line_start) do
    prefix = String.slice(source, 0, line_start)

    case ExprLayoutLexer.logical_lines(prefix) do
      {:ok, lines} ->
        Enum.reduce(lines, initial_state(), fn line, state -> advance_state(state, line) end)
    end
  end

  defp initial_state do
    %{indent_stack: [0], blocks: [], cont: nil}
  end

  @spec advance_state(state(), map()) :: state()
  defp advance_state(state, line) do
    state
    |> apply_indent_transitions(line)
    |> apply_line_semantics(line)
  end

  defp apply_indent_transitions(%{indent_stack: stack, cont: cont} = state, line) do
    indent = Map.get(line, :indent, 0)

    cond do
      cont in [:after_eq, :after_arrow] and indent > hd(stack) ->
        state

      indent > hd(stack) ->
        %{state | indent_stack: [indent | stack], cont: nil}

      indent < hd(stack) ->
        {new_stack, _} = pop_to_indent(stack, indent, [])
        blocks = block_stack_after_dedent(new_stack, state.blocks)
        %{state | indent_stack: new_stack, blocks: blocks, cont: nil}

      true ->
        %{state | cont: if(cont in [:after_eq, :after_arrow], do: nil, else: cont)}
    end
  end

  @spec apply_line_semantics(state(), map()) :: state()
  defp apply_line_semantics(state, line) do
    text = Map.get(line, :text, "")
    blocks = update_blocks(state.blocks, text)
    cont = line_cont(text)
    %{state | blocks: blocks, cont: cont}
  end

  @spec update_blocks([block_kind()], String.t()) :: [block_kind()]
  defp update_blocks(blocks, text) do
    trimmed = String.trim(text)

    blocks
    |> push_block_if(let_header_line?(trimmed), :let)
    |> pop_block_if(trimmed == "in", :let)
    |> push_block_if(case_of_line?(trimmed), :case)
  end

  @spec push_block_if([block_kind()], boolean(), block_kind()) :: [block_kind()]
  defp push_block_if(blocks, false, _kind), do: blocks
  defp push_block_if(blocks, true, kind), do: [kind | blocks]

  @spec pop_block_if([block_kind()], boolean(), block_kind()) :: [block_kind()]
  defp pop_block_if(blocks, false, _kind), do: blocks
  defp pop_block_if(blocks, true, kind), do: List.delete(blocks, kind)

  @spec line_cont(String.t()) :: cont_kind()
  defp line_cont(text) do
    trimmed = String.trim_trailing(text)

    cond do
      String.trim(trimmed) == "in" -> nil
      String.ends_with?(trimmed, "=") -> :after_eq
      String.ends_with?(trimmed, "->") -> :after_arrow
      true -> nil
    end
  end

  @spec let_header_line?(String.t()) :: boolean()
  defp let_header_line?(trimmed) do
    trimmed == "let" or
      (String.starts_with?(trimmed, "let ") and not String.contains?(trimmed, "="))
  end

  @spec case_of_line?(String.t()) :: boolean()
  defp case_of_line?(trimmed) do
    Regex.match?(~r/\sof\s*$/u, trimmed)
  end

  @spec increase_after_block_keyword?(String.t()) :: boolean()
  defp increase_after_block_keyword?(trimmed_prefix) do
    Regex.match?(~r/\b(?:let|then|else|where)\s*$/u, trimmed_prefix) or
      Regex.match?(~r/\bof\s*$/u, trimmed_prefix)
  end

  @spec type_declaration_head?(String.t()) :: boolean()
  defp type_declaration_head?(trimmed_line) do
    String.starts_with?(trimmed_line, "type ") and not String.starts_with?(trimmed_line, "type alias ")
  end

  @spec block_indent_column(state(), non_neg_integer()) :: non_neg_integer()
  defp block_indent_column(%{indent_stack: [0]}, base_column), do: max(base_column, Layout.indent_step())
  defp block_indent_column(%{indent_stack: stack}, _base_column), do: hd(stack)

  @spec block_stack_after_dedent([non_neg_integer()], [block_kind()]) :: [block_kind()]
  defp block_stack_after_dedent([0], blocks), do: List.delete(blocks, :case)
  defp block_stack_after_dedent(_stack, blocks), do: blocks

  @spec pop_to_indent([non_neg_integer()], non_neg_integer(), [non_neg_integer()]) ::
          {[non_neg_integer()], [non_neg_integer()]}
  defp pop_to_indent([top | _] = stack, indent, tokens) when top == indent, do: {stack, tokens}

  defp pop_to_indent([_top | rest], indent, tokens) do
    pop_to_indent(rest, indent, tokens)
  end

  defp pop_to_indent([], _indent, tokens), do: {[0], tokens}

  @spec line_start_at(String.t(), non_neg_integer()) :: non_neg_integer()
  defp line_start_at(source, offset) do
    prefix = String.slice(source, 0, offset)

    case :binary.matches(prefix, "\n") do
      [] -> 0
      matches -> elem(List.last(matches), 0) + 1
    end
  end

  @spec line_end_at(String.t(), non_neg_integer()) :: non_neg_integer()
  defp line_end_at(source, offset) do
    case :binary.match(String.slice(source, offset, String.length(source)), "\n") do
      :nomatch -> String.length(source)
      {rel, _len} -> offset + rel
    end
  end

  @spec leading_whitespace(String.t()) :: String.t()
  defp leading_whitespace(value), do: (Regex.run(~r/^[ \t]*/, value) || [""]) |> hd()

  @spec clamp_offset(String.t(), integer()) :: non_neg_integer()
  defp clamp_offset(source, offset), do: max(0, min(offset, String.length(source)))
end
