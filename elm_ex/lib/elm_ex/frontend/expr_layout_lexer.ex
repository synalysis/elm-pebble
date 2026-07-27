defmodule ElmEx.Frontend.ExprLayoutLexer do
  @moduledoc """
  Indentation-aware tokenizer for `elm_ex_expr_parser`.

  Physical newlines become explicit `{newline, line}` tokens; increased/decreased
  indentation (outside brackets) becomes `{indent, line}` / `{dedent, line}`.
  Yecc uses those tokens for Elm `let` bindings and `case` arms instead of a
  preprocessor that inserts `;` / `;;`.
  """

  alias ElmEx.Frontend.{Layout, LayoutRules}

  @type token() :: {atom(), non_neg_integer(), term()}
  @type line_info() :: %{
          line_no: pos_integer(),
          indent: non_neg_integer(),
          text: String.t(),
          paren_depth: non_neg_integer(),
          paren_at_start: non_neg_integer()
        }
  @type block_kind() :: :let | :case
  @type cont_kind() :: nil | :after_eq | :after_arrow | :after_value | :after_infix_rhs
  @type layout_mode() :: :default | :let_inline

  @doc """
  Tokenize expression source with significant layout.

  Single-line sources delegate to `:elm_ex_expr_lexer/1`. Multiline sources emit
  layout tokens between per-line Leex token runs.
  """
  @spec tokenize(String.t()) :: {:ok, [token()], pos_integer()} | {:error, term()}
  def tokenize(source) when is_binary(source) do
    trimmed = String.trim(source)

    if not String.contains?(trimmed, "\n") do
      :elm_ex_expr_lexer.string(String.to_charlist(trimmed))
    else
      tokenize_multiline(trimmed)
    end
  end

  @spec tokenize_multiline(String.t()) :: {:ok, [token()], pos_integer()} | {:error, term()}
  defp tokenize_multiline(source) do
    case logical_lines(source) do
      {:ok, lines} ->
        emit_layout_tokens(lines, [0], [], 0, [], nil, :default, nil)
    end
  end

  @doc false
  @spec logical_lines(String.t()) :: {:ok, [line_info()]}
  def logical_lines(source) when is_binary(source) do
    {:ok, split_logical_lines(source)}
  end

  @spec split_logical_lines(String.t()) :: [line_info()]
  defp split_logical_lines(source) do
    graphemes = String.graphemes(source)

    {lines, line_no, _line_start, _col, _mode, _escaped, paren, buf, line_indent, paren_at_line_start} =
      Enum.reduce(graphemes, {[], 1, true, 0, :code, false, 0, [], 0, 0}, fn ch, acc ->
        step_char(ch, acc)
      end)

    finalize_eof(lines, line_no, paren, buf, line_indent, paren_at_line_start)
  end

  defp finalize_eof(lines, line_no, paren, buf, line_indent, paren_at_line_start) do
    text = buf |> Enum.reverse() |> IO.iodata_to_binary() |> String.trim()

    lines =
      if text == "" do
        lines
      else
        [
          %{
            line_no: line_no,
            indent: line_indent,
            text: text,
            paren_depth: paren,
            paren_at_start: paren_at_line_start
          }
          | lines
        ]
      end

    Enum.reverse(lines)
  end

  defp step_char(ch, {lines, line_no, line_start, col, mode, escaped, paren, buf, line_indent, paren_at_line_start}) do
    cond do
      mode == :string ->
        handle_string_char(
          ch,
          escaped,
          lines,
          line_no,
          line_start,
          col,
          paren,
          buf,
          line_indent,
          paren_at_line_start
        )

      mode == :char ->
        handle_char_char(
          ch,
          escaped,
          lines,
          line_no,
          line_start,
          col,
          paren,
          buf,
          line_indent,
          paren_at_line_start
        )

      ch == "\n" ->
        finalize_line(lines, line_no, paren, buf, line_indent, paren_at_line_start, col)

      line_start and ch in [" ", "\t"] and paren == 0 ->
        indent = line_indent + tab_width(ch)

        {lines, line_no, true, col + 1, :code, false, paren, buf, indent,
         paren_at_line_start}

      line_start and ch == "\r" ->
        {lines, line_no, line_start, col + 1, :code, false, paren, buf, line_indent,
         paren_at_line_start}

      true ->
        {next_mode, next_escaped, next_paren, next_buf, next_line_start} =
          code_char(ch, escaped, mode, paren, buf, line_start)

        {lines, line_no, next_line_start, col + 1, next_mode, next_escaped, next_paren, next_buf,
         line_indent, paren_at_line_start}
    end
  end

  defp handle_string_char(
         ch,
         escaped,
         lines,
         line_no,
         _line_start,
         col,
         paren,
         buf,
         line_indent,
         paren_at_line_start
       ) do
    next_escaped = ch == "\\" and not escaped
    next_mode = if not escaped and ch == "\"", do: :code, else: :string

    {lines, line_no, false, col + 1, next_mode, next_escaped, paren, [ch | buf], line_indent,
     paren_at_line_start}
  end

  defp handle_char_char(
         ch,
         escaped,
         lines,
         line_no,
         _line_start,
         col,
         paren,
         buf,
         line_indent,
         paren_at_line_start
       ) do
    next_escaped = ch == "\\" and not escaped
    next_mode = if not escaped and ch == "'", do: :code, else: :char

    {lines, line_no, false, col + 1, next_mode, next_escaped, paren, [ch | buf], line_indent,
     paren_at_line_start}
  end

  defp code_char(ch, _escaped, _mode, paren, buf, _line_start) do
    cond do
      ch == "\"" ->
        {:string, false, paren, [ch | buf], false}

      ch == "'" ->
        {:char, false, paren, [ch | buf], false}

      ch == "(" ->
        {:code, false, paren + 1, [ch | buf], false}

      ch == ")" ->
        {:code, false, max(paren - 1, 0), [ch | buf], false}

      ch == "[" ->
        {:code, false, paren + 1, [ch | buf], false}

      ch == "]" ->
        {:code, false, max(paren - 1, 0), [ch | buf], false}

      ch == "{" ->
        {:code, false, paren + 1, [ch | buf], false}

      ch == "}" ->
        {:code, false, max(paren - 1, 0), [ch | buf], false}

      true ->
        {:code, false, paren, [ch | buf], false}
    end
  end

  defp finalize_line(lines, line_no, paren, buf, line_indent, paren_at_line_start, _col) do
    text = buf |> Enum.reverse() |> IO.iodata_to_binary() |> String.trim()

    lines =
      if text == "" do
        lines
      else
        [
          %{
            line_no: line_no,
            indent: line_indent,
            text: text,
            paren_depth: paren,
            paren_at_start: paren_at_line_start
          }
          | lines
        ]
      end

    {lines, line_no + 1, true, 0, :code, false, paren, [], 0, paren}
  end

  defp tab_width("\t"), do: Layout.tab_width("\t")
  defp tab_width(_), do: Layout.tab_width(" ")

  @spec emit_layout_tokens(
          [line_info()],
          [non_neg_integer()],
          [token()],
          non_neg_integer(),
          [block_kind()],
          cont_kind(),
          layout_mode(),
          non_neg_integer() | nil
        ) :: {:ok, [token()], pos_integer()} | {:error, term()}
  defp emit_layout_tokens([], stack, tokens, last_line, _blocks, _cont, _mode, _expr_indent) do
    {_stack, dedent_tokens} = finalize_dedents(stack, last_line, [])
    {:ok, tokens ++ dedent_tokens, max(last_line, 1)}
  end

  defp emit_layout_tokens([line | rest], stack, tokens, last_line, blocks, cont, mode, expr_indent) do
    {stack, layout_tokens, blocks, cont, mode, expr_indent} =
      layout_tokens_for_line(line, stack, last_line, blocks, cont, mode, expr_indent)

    case :elm_ex_expr_lexer.string(String.to_charlist(line.text)) do
      {:ok, line_tokens, _} ->
        merged = tokens ++ layout_tokens ++ line_tokens
        {blocks, cont, mode} = next_layout_state(blocks, cont, mode, line_tokens)
        emit_layout_tokens(rest, stack, merged, line.line_no, blocks, cont, mode, expr_indent)

      {:error, reason, _} ->
        {:error, reason}
    end
  end

  @spec next_layout_state([block_kind()], cont_kind(), layout_mode(), [token()]) ::
          {[block_kind()], cont_kind(), layout_mode()}
  defp next_layout_state(blocks, _cont, mode, line_tokens) do
    kinds = token_kinds(line_tokens)

    blocks =
      blocks
      |> push_block_if(:let_kw in kinds, :let)
      |> pop_block_if(:in_kw in kinds, :let)
      |> push_block_if(:of_kw in kinds, :case)

    mode =
      cond do
        :in_kw in kinds -> :default
        :let_kw in kinds and :eq in kinds -> :let_inline
        :let_kw in kinds -> :default
        true -> mode
      end

    cont =
      cond do
        :in_kw in kinds -> nil
        last_token_kind(line_tokens) == :eq -> :after_eq
        last_token_kind(line_tokens) == :arrow -> :after_arrow
        last_token_kind(line_tokens) in [:apply_left, :shl, :shr] -> :after_infix_rhs
        value_line_end?(line_tokens) -> :after_value
        true -> nil
      end

    {blocks, cont, mode}
  end

  defp push_block_if(blocks, false, _kind), do: blocks
  defp push_block_if(blocks, true, kind), do: [kind | blocks]

  defp pop_block_if(blocks, false, _kind), do: blocks
  defp pop_block_if(blocks, true, kind), do: List.delete(blocks, kind)

  defp token_kinds(tokens) do
    Enum.map(tokens, fn
      {k, _, _} -> k
      {k, _} -> k
    end)
  end

  defp last_token_kind(tokens) do
    case List.last(tokens) do
      {kind, _, _} -> kind
      {kind, _} -> kind
      _ -> nil
    end
  end

  defp value_line_end?(tokens) do
    last_token_kind(tokens) in [
      :lower_qid,
      :upper_qid,
      :int_lit,
      :float_lit,
      :string_lit,
      :char_lit,
      :rparen,
      :rbracket,
      :rbrace
    ]
  end

  defp layout_tokens_for_line(
         %{line_no: line_no, indent: indent, paren_at_start: 0, text: text},
         stack,
         last_line,
         blocks,
         cont,
         mode,
         expr_indent
       ) do
    indent_rel = indent_relation(indent, stack)

    {expr_close_tokens, expr_indent} =
      if LayoutRules.in_line_start?(text) do
        {[], expr_indent}
      else
        maybe_close_expr_indent(expr_indent, indent, stack, line_no, text, blocks)
      end

    tokens =
      expr_close_tokens ++
        sibling_or_newline_tokens(line_no, indent, stack, last_line, blocks, cont, text, indent_rel, mode)

    cond do
      let_inline_sibling?(mode, blocks, text) ->
        {stack, tokens ++ [{LayoutRules.let_binding_sep(), line_no}], blocks, nil, mode, nil}

      application_arg_continuation?(cont, text) ->
        {stack, tokens, blocks, nil, mode, expr_indent}

      pipe_value_continuation?(cont, text) ->
        {stack, tokens, blocks, nil, mode, expr_indent}

      infix_rhs_continuation?(cont, text) ->
        {stack, tokens, blocks, nil, mode, expr_indent}

      expression_continuation?(cont, text) and indent > hd(stack) ->
        {stack, tokens ++ [{:indent, line_no}], blocks, nil, mode, indent}

      indent > hd(stack) ->
        {[indent | stack], tokens ++ [{:indent, line_no}], blocks, nil, mode, nil}

      indent < hd(stack) ->
        cond do
          LayoutRules.in_line_start?(text) ->
            {new_stack, dedent_count} = dedents_before_in(stack, indent, expr_indent)
            dedent_tokens = List.duplicate({:dedent, line_no}, dedent_count)
            {new_stack, tokens ++ dedent_tokens, blocks, nil, mode, nil}

          LayoutRules.else_line_start?(text) ->
            {new_stack, dedent_count} = dedents_before_block_end(stack, indent)
            dedent_tokens = List.duplicate({:dedent, line_no}, dedent_count)
            {new_stack, tokens ++ dedent_tokens, blocks, nil, mode, nil}

          sibling_line?(blocks, indent, text) ->
            {new_stack, dedent_tokens} = pop_to_indent(stack, indent, line_no, [])

            {new_stack, tokens ++ dedent_tokens ++ sibling_sep_token(blocks, line_no), blocks, nil, mode,
             nil}

          true ->
            {new_stack, dedent_tokens} = pop_to_indent(stack, indent, line_no, [])
            {new_stack, tokens ++ dedent_tokens, block_stack_after_dedent(new_stack, blocks), nil, mode, nil}
        end

      LayoutRules.in_line_start?(text) ->
        {new_stack, dedent_count} = dedents_before_in(stack, indent, expr_indent)
        dedent_tokens = List.duplicate({:dedent, line_no}, dedent_count)
        {new_stack, tokens ++ dedent_tokens, blocks, nil, mode, nil}

      LayoutRules.else_line_start?(text) ->
        {new_stack, dedent_count} = dedents_before_block_end(stack, indent)
        dedent_tokens = List.duplicate({:dedent, line_no}, dedent_count)
        {new_stack, tokens ++ dedent_tokens, blocks, nil, mode, nil}

      true ->
        {stack, tokens, blocks, cont, mode, expr_indent}
    end
  end

  defp layout_tokens_for_line(
         %{line_no: line_no, paren_at_start: depth, text: text},
         stack,
         last_line,
         blocks,
         cont,
         mode,
         expr_indent
       )
       when depth > 0 do
    {stack, bracket_layout_tokens(line_no, last_line, blocks, cont, text), blocks, cont, mode,
     expr_indent}
  end

  defp dedents_before_in(stack, indent, expr_indent) do
    {stack, count} = dedents_before_block_end(stack, indent)
    {stack, count + if(expr_indent != nil, do: 1, else: 0)}
  end

  defp dedents_before_block_end(stack, indent) do
    {stack, count} = pop_strictly_above_stack(stack, indent)

    if count == 0 and stack != [0] and hd(stack) == indent do
      {tl(stack), 1}
    else
      {stack, count}
    end
  end

  defp pop_strictly_above_stack([top | rest], indent) when top > indent do
    {new_stack, count} = pop_strictly_above_stack(rest, indent)
    {new_stack, count + 1}
  end

  defp pop_strictly_above_stack(stack, _indent), do: {stack, 0}

  defp expression_continuation?(cont, text) do
    not block_keyword_line?(text) and
      (cont in [:after_eq, :after_arrow] or LayoutRules.pipe_continuation?(text))
  end

  defp application_arg_continuation?(cont, text) do
    cont == :after_value and LayoutRules.application_continuation?(text)
  end

  defp pipe_value_continuation?(cont, text) do
    cont == :after_value and LayoutRules.value_line_continuation?(text)
  end

  defp infix_rhs_continuation?(cont, text) do
    cont == :after_infix_rhs and LayoutRules.infix_rhs_line_start?(text)
  end

  @spec bracket_layout_tokens(
          pos_integer(),
          non_neg_integer(),
          [block_kind()],
          cont_kind(),
          String.t()
        ) :: [token()]
  defp bracket_layout_tokens(_line_no, 0, _blocks, _cont, _text), do: []

  defp bracket_layout_tokens(line_no, _last_line, blocks, cont, text) do
    cond do
      :case in blocks and LayoutRules.case_arm_start?(text) and
          cont in [:after_value, :after_arrow] ->
        [{LayoutRules.case_arm_sep(), line_no}]

      :let in blocks and LayoutRules.let_binding_start?(text) and
          cont in [:after_value, :after_arrow] ->
        [{LayoutRules.let_binding_sep(), line_no}]

      true ->
        []
    end
  end

  defp block_keyword_line?(text) do
    trimmed = String.trim(text)

    Regex.match?(~r/^(let|case|if)\b/u, trimmed) or LayoutRules.in_line_start?(text) or
      LayoutRules.else_line_start?(text)
  end

  defp maybe_close_expr_indent(nil, _indent, _stack, _line_no, _text, _blocks), do: {[], nil}

  defp maybe_close_expr_indent(expr_indent, indent, stack, line_no, text, blocks)
       when expr_indent != nil do
    cond do
      LayoutRules.in_line_start?(text) ->
        {[], nil}

      indent <= hd(stack) and sibling_line?(blocks, indent, text) ->
        {[{:dedent, line_no}], nil}

      true ->
        {[], expr_indent}
    end
  end

  @spec indent_relation(non_neg_integer(), [non_neg_integer()]) :: :enter | :exit | :same
  defp indent_relation(indent, stack) do
    cond do
      indent > hd(stack) -> :enter
      indent < hd(stack) -> :exit
      true -> :same
    end
  end

  @spec sibling_or_newline_tokens(
          pos_integer(),
          non_neg_integer(),
          [non_neg_integer()],
          non_neg_integer(),
          [block_kind()],
          cont_kind(),
          String.t(),
          :enter | :exit | :same,
          layout_mode()
        ) :: [token()]
  defp sibling_or_newline_tokens(_line_no, _indent, _stack, 0, _blocks, _cont, _text, _rel, _mode), do: []

  defp sibling_or_newline_tokens(line_no, indent, stack, _last_line, blocks, cont, text, rel, mode) do
    if layout_line_start?(text) or (mode == :let_inline and let_block?(blocks) and LayoutRules.let_binding_start?(text)) do
      []
    else
      sibling_or_newline_tokens_rel(line_no, indent, stack, blocks, cont, text, rel)
    end
  end

  defp layout_line_start?(text) do
    LayoutRules.in_line_start?(text) or LayoutRules.else_line_start?(text)
  end

  defp sibling_or_newline_tokens_rel(line_no, indent, stack, blocks, nil, text, :exit) do
    cond do
      layout_line_start?(text) ->
        []

      LayoutRules.pipe_continuation?(text) ->
        []

      sibling_line?(blocks, indent, text) ->
        []

      true ->
        sibling_binding_or_newline(line_no, indent, stack, blocks, text)
    end
  end

  defp sibling_or_newline_tokens_rel(line_no, indent, stack, blocks, nil, text, :enter) do
    cond do
      LayoutRules.pipe_continuation?(text) ->
        [{:newline, line_no}]

      true ->
        sibling_binding_or_newline(line_no, indent, stack, blocks, text)
    end
  end

  defp sibling_or_newline_tokens_rel(line_no, indent, stack, blocks, nil, text, :same) do
    if layout_line_start?(text) do
      []
    else
      sibling_binding_or_newline(line_no, indent, stack, blocks, text)
    end
  end

  defp sibling_or_newline_tokens_rel(line_no, indent, stack, blocks, :after_infix_rhs, text, _rel) do
    if LayoutRules.infix_rhs_line_start?(text) do
      []
    else
      sibling_or_newline_tokens_rel(line_no, indent, stack, blocks, nil, text, :same)
    end
  end

  defp sibling_or_newline_tokens_rel(line_no, indent, stack, blocks, :after_value, text, rel) do
    if LayoutRules.application_continuation?(text) or LayoutRules.value_line_continuation?(text) do
      []
    else
      sibling_or_newline_tokens_rel(line_no, indent, stack, blocks, nil, text, rel)
    end
  end

  defp sibling_or_newline_tokens_rel(line_no, _indent, _stack, _blocks, cont, _text, _rel)
       when cont in [:after_eq, :after_arrow] do
    [{:newline, line_no}]
  end

  defp let_block?(blocks), do: :let in blocks

  @spec let_inline_sibling?(layout_mode(), [block_kind()], String.t()) :: boolean()
  defp let_inline_sibling?(:let_inline, blocks, text) do
    let_block?(blocks) and LayoutRules.let_binding_start?(text)
  end

  defp let_inline_sibling?(_mode, _blocks, _text), do: false

  @spec sibling_binding_or_newline(
          pos_integer(),
          non_neg_integer(),
          [non_neg_integer()],
          [block_kind()],
          String.t()
        ) :: [token()]
  defp sibling_binding_or_newline(line_no, indent, stack, blocks, text) do
    cond do
      :let in blocks and indent == hd(stack) and LayoutRules.let_binding_start?(text) ->
        [{LayoutRules.let_binding_sep(), line_no}]

      :case in blocks and indent == hd(stack) and LayoutRules.case_arm_start?(text) ->
        [{LayoutRules.case_arm_sep(), line_no}]

      true ->
        [{:newline, line_no}]
    end
  end

  @spec sibling_line?([block_kind()], non_neg_integer(), String.t()) :: boolean()
  defp sibling_line?(blocks, _indent, text) do
    (:let in blocks and LayoutRules.let_binding_start?(text)) or
      (:case in blocks and LayoutRules.case_arm_start?(text))
  end

  @spec sibling_sep_token([block_kind()], pos_integer()) :: [token()]
  defp sibling_sep_token(blocks, line_no) do
    cond do
      :let in blocks -> [{LayoutRules.let_binding_sep(), line_no}]
      :case in blocks -> [{LayoutRules.case_arm_sep(), line_no}]
      true -> [{:newline, line_no}]
    end
  end

  @spec block_stack_after_dedent([non_neg_integer()], [block_kind()]) :: [block_kind()]
  defp block_stack_after_dedent([0], blocks), do: List.delete(blocks, :case)
  defp block_stack_after_dedent(_stack, blocks), do: blocks

  @spec pop_to_indent([non_neg_integer()], non_neg_integer(), pos_integer(), [token()]) ::
          {[non_neg_integer()], [token()]}
  defp pop_to_indent([top | _] = stack, indent, _line_no, tokens) when top == indent do
    {stack, tokens}
  end

  defp pop_to_indent([_top | rest], indent, line_no, tokens) do
    pop_to_indent(rest, indent, line_no, [{:dedent, line_no} | tokens])
  end

  defp pop_to_indent([], _indent, line_no, tokens) do
    {[0], [{:dedent, line_no} | tokens]}
  end

  defp finalize_dedents([0], _line_no, tokens), do: {[0], tokens}

  defp finalize_dedents([_ | rest], line_no, tokens) do
    finalize_dedents(rest, line_no, [{:dedent, line_no} | tokens])
  end
end
