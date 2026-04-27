defmodule Ide.Formatter.Printer.Expression do
  @moduledoc false

  @spec normalize_nested_call_list_arguments(String.t()) :: String.t()
  def normalize_nested_call_list_arguments(source) when is_binary(source) do
    source
    |> String.split("\n", trim: false)
    |> Enum.map(&expand_nested_call_list_line/1)
    |> List.flatten()
    |> Enum.join("\n")
  end

  @spec normalize_multiline_nested_call_list_arguments(String.t()) :: String.t()
  def normalize_multiline_nested_call_list_arguments(source) when is_binary(source) do
    source
    |> String.split("\n", trim: false)
    |> rewrite_multiline_nested_call_lines()
    |> Enum.join("\n")
  end

  @spec normalize_multiline_nested_call_block_indentation(String.t()) :: String.t()
  def normalize_multiline_nested_call_block_indentation(source) when is_binary(source) do
    source
    |> String.split("\n", trim: false)
    |> rewrite_nested_call_block_indentation()
    |> Enum.join("\n")
  end

  @spec normalize_multiline_call_argument_alignment(String.t()) :: String.t()
  def normalize_multiline_call_argument_alignment(source) when is_binary(source) do
    {lines_rev, _state} =
      source
      |> String.split("\n", trim: false)
      |> Enum.reduce({[], %{in_call: false, call_indent: nil, arg_indent: nil}}, fn line,
                                                                                    {acc, state} ->
        trimmed = String.trim(line)
        indent = leading_indent(line)

        cond do
          not state.in_call and starts_with_trimmed?(line, "(") and
              not String.contains?(trimmed, ")") ->
            {[line | acc], %{in_call: true, call_indent: indent, arg_indent: nil}}

          state.in_call and starts_with_trimmed?(line, ")") and indent <= (state.call_indent || 0) ->
            {[line | acc], %{in_call: false, call_indent: nil, arg_indent: nil}}

          state.in_call and trimmed != "" and is_nil(state.arg_indent) ->
            {[line | acc], %{state | arg_indent: indent}}

          state.in_call and is_integer(state.arg_indent) and starts_with_trimmed?(line, "[") and
              indent < state.arg_indent ->
            normalized = String.duplicate(" ", state.arg_indent) <> String.trim_leading(line)
            {[normalized | acc], state}

          true ->
            {[line | acc], state}
        end
      end)

    lines_rev
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  @spec normalize_inline_if_then_else(String.t()) :: String.t()
  def normalize_inline_if_then_else(source) when is_binary(source) do
    source
    |> String.split("\n", trim: false)
    |> Enum.map(&expand_inline_if_line/1)
    |> List.flatten()
    |> Enum.join("\n")
  end

  @spec normalize_multiline_if_alignment(String.t()) :: String.t()
  def normalize_multiline_if_alignment(source) when is_binary(source) do
    {lines_rev, _state} =
      source
      |> String.split("\n", trim: false)
      |> Enum.reduce({[], nil}, fn line, {acc, state} ->
        {normalized, next_state} = normalize_multiline_if_line(line, state)
        {[normalized | acc], next_state}
      end)

    lines_rev
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  @spec normalize_multiline_tuple_alignment(String.t()) :: String.t()
  def normalize_multiline_tuple_alignment(source) when is_binary(source) do
    {lines_rev, _tuple_indent} =
      source
      |> String.split("\n", trim: false)
      |> Enum.reduce({[], nil}, fn line, {acc, tuple_indent} ->
        trimmed = String.trim(line)

        cond do
          is_nil(tuple_indent) ->
            case tuple_open_indent(line) do
              nil ->
                {[line | acc], nil}

              indent ->
                {[line | acc], indent}
            end

          is_integer(tuple_indent) and starts_with_trimmed?(line, ",") ->
            {[String.duplicate(" ", tuple_indent) <> String.trim_leading(line) | acc],
             tuple_indent}

          is_integer(tuple_indent) and starts_with_trimmed?(line, ")") ->
            {[line | acc], nil}

          is_integer(tuple_indent) and trimmed == "" ->
            {[line | acc], tuple_indent}

          true ->
            {[line | acc], nil}
        end
      end)

    lines_rev
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  @spec normalize_record_tuple_comma_pair(String.t()) :: String.t()
  def normalize_record_tuple_comma_pair(source) when is_binary(source) do
    {lines_rev, _tuple_indent} =
      source
      |> String.split("\n", trim: false)
      |> Enum.reduce({[], nil}, fn line, {acc, tuple_indent} ->
        cond do
          is_nil(tuple_indent) and opens_record_tuple_pair?(line) ->
            {[line | acc], leading_indent(line)}

          is_integer(tuple_indent) and starts_with_trimmed?(line, ",") ->
            normalized = String.duplicate(" ", tuple_indent) <> String.trim_leading(line)
            {[normalized | acc], tuple_indent}

          is_integer(tuple_indent) and starts_with_trimmed?(line, ")") ->
            {[line | acc], nil}

          true ->
            {[line | acc], tuple_indent}
        end
      end)

    lines_rev
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  @spec normalize_inline_let_in(String.t()) :: String.t()
  def normalize_inline_let_in(source) when is_binary(source) do
    {lines_rev, _pending_let_indent} =
      source
      |> String.split("\n", trim: false)
      |> Enum.reduce({[], nil}, fn line, {acc, pending_let_indent} ->
        trimmed = String.trim(line)
        indent = leading_indent(line)

        cond do
          trimmed == "let" ->
            {[line | acc], indent}

          is_integer(pending_let_indent) ->
            case expand_binding_line_after_let(trimmed, pending_let_indent) do
              {:expanded, expanded_lines} ->
                {Enum.reverse(expanded_lines) ++ acc, nil}

              :no_change ->
                {[line | acc], nil}
            end

          String.starts_with?(trimmed, "let ") ->
            case expand_inline_let_expression(trimmed, indent) do
              {:expanded, expanded_lines} ->
                {Enum.reverse(expanded_lines) ++ acc, nil}

              :no_change ->
                {[line | acc], nil}
            end

          true ->
            {[line | acc], nil}
        end
      end)

    lines_rev
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  @spec normalize_range_expressions(String.t()) :: String.t()
  def normalize_range_expressions(source) when is_binary(source) do
    rewrite_range_expressions(source)
  end

  @spec rewrite_range_expressions(term()) :: term()
  defp rewrite_range_expressions(source) do
    do_rewrite_range_expressions(source, "")
  end

  @spec do_rewrite_range_expressions(term(), term()) :: term()
  defp do_rewrite_range_expressions(<<"[", rest::binary>>, acc) do
    case take_until(rest, "]") do
      {:ok, inside, tail} ->
        if String.contains?(inside, "\n") do
          do_rewrite_range_expressions(tail, acc <> "[" <> inside <> "]")
        else
          case split_once(inside, "..") do
            {from, to} ->
              replacement = "List.range #{String.trim(from)} #{String.trim(to)}"
              do_rewrite_range_expressions(tail, acc <> replacement)

            :error ->
              do_rewrite_range_expressions(tail, acc <> "[" <> inside <> "]")
          end
        end

      _ ->
        do_rewrite_range_expressions(rest, acc <> "[")
    end
  end

  defp do_rewrite_range_expressions(<<char::utf8, rest::binary>>, acc),
    do: do_rewrite_range_expressions(rest, acc <> <<char::utf8>>)

  defp do_rewrite_range_expressions("", acc), do: acc

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

  @spec take_until(term(), term()) :: term()
  defp take_until(value, delimiter) do
    case :binary.match(value, delimiter) do
      {idx, len} ->
        {
          :ok,
          binary_part(value, 0, idx),
          binary_part(value, idx + len, byte_size(value) - idx - len)
        }

      :nomatch ->
        :error
    end
  end

  @spec expand_inline_if_line(term()) :: term()
  defp expand_inline_if_line(line) do
    trimmed = String.trim_leading(line)
    indent = leading_indent(line)

    case leading_comma_if_expression(trimmed) do
      {:ok, if_expression} ->
        expand_inline_if_expression(if_expression, indent, ", ", indent + 2, line)

      :error ->
        if String.starts_with?(trimmed, "if ") do
          expand_inline_if_expression(trimmed, indent, "", indent, line)
        else
          [line]
        end
    end
  end

  @spec leading_comma_if_expression(term()) :: term()
  defp leading_comma_if_expression(trimmed) when is_binary(trimmed) do
    if String.starts_with?(trimmed, ",") do
      after_comma = String.trim_leading(String.trim_leading(trimmed, ","))

      if String.starts_with?(after_comma, "if ") do
        {:ok, after_comma}
      else
        :error
      end
    else
      :error
    end
  end

  @spec expand_inline_if_expression(term(), term(), term(), term(), term()) :: term()
  defp expand_inline_if_expression(if_expression, indent, prefix, else_indent, fallback_line) do
    case split_if_then_else(if_expression) do
      {:ok, condition, then_expr, else_expr} ->
        branch_indent = else_indent + 4

        [
          String.duplicate(" ", indent) <>
            prefix <> "if " <> collapse_spaces(condition) <> " then",
          String.duplicate(" ", branch_indent) <> String.trim(then_expr),
          "",
          String.duplicate(" ", else_indent) <> "else",
          String.duplicate(" ", branch_indent) <> String.trim(else_expr)
        ]

      :error ->
        [fallback_line]
    end
  end

  @spec normalize_multiline_if_line(term(), term()) :: term()
  defp normalize_multiline_if_line(line, state) do
    trimmed = String.trim(line)

    cond do
      is_nil(state) ->
        case multiline_if_layout(line) do
          {:ok, layout} -> {line, Map.put(layout, :phase, :then)}
          :error -> {line, nil}
        end

      trimmed == "" ->
        {line, state}

      state.phase == :then and leading_indent(line) <= state.branch_indent and trimmed == "else" ->
        {String.duplicate(" ", state.else_indent) <> "else", %{state | phase: :else}}

      state.phase == :then ->
        {normalize_if_branch_line(line, state.branch_indent), %{state | phase: :waiting_else}}

      state.phase == :waiting_else and leading_indent(line) <= state.branch_indent and
          trimmed == "else" ->
        {String.duplicate(" ", state.else_indent) <> "else", %{state | phase: :else}}

      state.phase == :waiting_else ->
        {line, state}

      state.phase == :else ->
        {normalize_if_branch_line(line, state.branch_indent), nil}
    end
  end

  @spec multiline_if_layout(term()) :: term()
  defp multiline_if_layout(line) do
    trimmed = String.trim_leading(line)
    indent = leading_indent(line)

    cond do
      not String.ends_with?(trimmed, " then") ->
        :error

      String.starts_with?(trimmed, "if ") ->
        {:ok, %{else_indent: indent, branch_indent: indent + 4}}

      match?({:ok, _}, leading_comma_if_expression(String.trim_trailing(trimmed, " then"))) ->
        {:ok, %{else_indent: indent + 2, branch_indent: indent + 6}}

      true ->
        :error
    end
  end

  @spec normalize_if_branch_line(term(), term()) :: term()
  defp normalize_if_branch_line(line, branch_indent) do
    String.duplicate(" ", branch_indent) <> String.trim_leading(line)
  end

  @spec expand_nested_call_list_line(term()) :: term()
  defp expand_nested_call_list_line(line) do
    indent = leading_indent(line)
    trimmed = String.trim_leading(line)

    case parse_nested_call_list_line(trimmed) do
      {:ok, outer, inner_head, list_items, trailing_args} ->
        base = String.duplicate(" ", indent)
        inner_base = String.duplicate(" ", indent + 4)
        list_base = String.duplicate(" ", indent + 8)

        list_lines =
          case list_items do
            [] ->
              []

            [first | rest] ->
              [list_base <> "[ " <> first] ++
                Enum.map(rest, &(list_base <> ", " <> &1)) ++ [list_base <> "]"]
          end

        arg_lines = Enum.map(trailing_args, &(list_base <> &1))

        [
          base <> outer,
          inner_base <> "(" <> inner_head
        ] ++ list_lines ++ arg_lines ++ [inner_base <> ")"]

      :no_change ->
        [line]
    end
  end

  @spec parse_nested_call_list_line(term()) :: term()
  defp parse_nested_call_list_line(trimmed) when is_binary(trimmed) do
    cond do
      not String.starts_with?(trimmed, ",") ->
        :no_change

      not String.ends_with?(trimmed, ")") ->
        :no_change

      true ->
        case split_outer_inner(trimmed) do
          {:ok, outer, inner} ->
            with {:ok, inner_head, list_inside, after_list} <- split_inner_list_call(inner),
                 list_items when is_list(list_items) <- split_top_level_csv(list_inside),
                 true <- length(list_items) >= 2,
                 trailing_args when is_list(trailing_args) <-
                   split_top_level_space_args(after_list),
                 true <- length(trailing_args) >= 2 do
              {:ok, outer, inner_head, list_items, trailing_args}
            else
              _ -> :no_change
            end

          :error ->
            :no_change
        end
    end
  end

  @spec split_outer_inner(term()) :: term()
  defp split_outer_inner(trimmed) do
    case :binary.match(trimmed, " (") do
      :nomatch ->
        :error

      {idx, _len} ->
        outer = binary_part(trimmed, 0, idx) |> String.trim_trailing()
        inner = binary_part(trimmed, idx + 2, byte_size(trimmed) - idx - 3) |> String.trim()

        if outer == "" or inner == "" do
          :error
        else
          {:ok, outer, inner}
        end
    end
  end

  @spec split_inner_list_call(term()) :: term()
  defp split_inner_list_call(inner) do
    if String.contains?(inner, "\"") do
      :error
    else
      case :binary.match(inner, " [") do
        :nomatch ->
          :error

        {idx, _len} ->
          inner_head = binary_part(inner, 0, idx) |> String.trim()
          rest = binary_part(inner, idx + 2, byte_size(inner) - idx - 2)

          case :binary.match(rest, "]") do
            :nomatch ->
              :error

            {list_end, _len2} ->
              list_inside = binary_part(rest, 0, list_end)

              after_list =
                binary_part(rest, list_end + 1, byte_size(rest) - list_end - 1) |> String.trim()

              if inner_head == "" do
                :error
              else
                {:ok, inner_head, list_inside, after_list}
              end
          end
      end
    end
  end

  @spec split_top_level_space_args(term()) :: term()
  defp split_top_level_space_args(value) do
    value
    |> String.split(" ", trim: true)
    |> Enum.reject(&(&1 == ""))
  end

  @spec rewrite_multiline_nested_call_lines(term()) :: term()
  defp rewrite_multiline_nested_call_lines([]), do: []

  defp rewrite_multiline_nested_call_lines([line | rest]) do
    case parse_multiline_nested_call_start(line) do
      {:ok, indent, outer, inner_head, first_item} ->
        case collect_multiline_nested_call(rest, [first_item]) do
          {:ok, remaining, items, trailing_args} ->
            emit_multiline_nested_call(indent, outer, inner_head, items, trailing_args) ++
              rewrite_multiline_nested_call_lines(remaining)

          :error ->
            [line | rewrite_multiline_nested_call_lines(rest)]
        end

      :error ->
        [line | rewrite_multiline_nested_call_lines(rest)]
    end
  end

  @spec rewrite_nested_call_block_indentation(term()) :: term()
  defp rewrite_nested_call_block_indentation([]), do: []

  defp rewrite_nested_call_block_indentation([outer_line, call_line | rest]) do
    outer_trimmed = String.trim_leading(outer_line)
    call_trimmed = String.trim_leading(call_line)

    cond do
      not String.starts_with?(outer_trimmed, ",") ->
        [outer_line | rewrite_nested_call_block_indentation([call_line | rest])]

      not String.starts_with?(call_trimmed, "(") or String.contains?(call_trimmed, ")") ->
        [outer_line | rewrite_nested_call_block_indentation([call_line | rest])]

      true ->
        outer_indent = leading_indent(outer_line)

        case collect_nested_call_block_lines(rest, []) do
          {:ok, body_lines, close_line, remaining} ->
            if nested_call_block_candidate?(body_lines) do
              call_indent = String.duplicate(" ", outer_indent + 4)
              arg_indent = String.duplicate(" ", outer_indent + 8)

              normalized_call_line = call_indent <> String.trim_leading(call_line)

              normalized_body_lines =
                Enum.map(body_lines, fn body_line ->
                  trimmed = String.trim_leading(body_line)

                  if trimmed == "" do
                    body_line
                  else
                    arg_indent <> trimmed
                  end
                end)

              normalized_close_line = call_indent <> String.trim_leading(close_line)

              [
                outer_line,
                normalized_call_line
                | normalized_body_lines ++
                    [normalized_close_line | rewrite_nested_call_block_indentation(remaining)]
              ]
            else
              [outer_line | rewrite_nested_call_block_indentation([call_line | rest])]
            end

          :error ->
            [outer_line | rewrite_nested_call_block_indentation([call_line | rest])]
        end
    end
  end

  defp rewrite_nested_call_block_indentation([line]), do: [line]

  @spec collect_nested_call_block_lines(term(), term()) :: term()
  defp collect_nested_call_block_lines([], _acc), do: :error

  defp collect_nested_call_block_lines([line | rest], acc) do
    trimmed = String.trim_leading(line)

    if String.starts_with?(trimmed, ")") do
      {:ok, Enum.reverse(acc), line, rest}
    else
      collect_nested_call_block_lines(rest, [line | acc])
    end
  end

  @spec nested_call_block_candidate?(term()) :: term()
  defp nested_call_block_candidate?(body_lines) when is_list(body_lines) do
    has_list_open? =
      Enum.any?(body_lines, fn line ->
        String.trim_leading(line) |> String.starts_with?("[")
      end)

    comma_lines =
      Enum.filter(body_lines, fn line ->
        String.trim_leading(line) |> String.starts_with?(",")
      end)

    comma_lines_are_tuple_items? =
      comma_lines != [] and
        Enum.all?(comma_lines, fn line ->
          String.trim_leading(line) |> String.starts_with?(", (")
        end)

    scalar_tail_lines =
      case Enum.find_index(body_lines, fn line ->
             String.trim_leading(line) |> String.starts_with?("]")
           end) do
        nil -> []
        idx -> body_lines |> Enum.drop(idx + 1) |> Enum.reject(&(String.trim(&1) == ""))
      end

    has_scalar_tail? =
      length(scalar_tail_lines) >= 2 and
        Enum.all?(scalar_tail_lines, fn line ->
          trimmed = String.trim_leading(line)

          trimmed != "" and
            not String.starts_with?(trimmed, "[") and
            not String.starts_with?(trimmed, ",") and
            not String.starts_with?(trimmed, "]") and
            not String.starts_with?(trimmed, "(") and
            not String.starts_with?(trimmed, ")")
        end)

    has_list_open? and comma_lines_are_tuple_items? and has_scalar_tail?
  end

  @spec parse_multiline_nested_call_start(term()) :: term()
  defp parse_multiline_nested_call_start(line) do
    indent = leading_indent(line)
    trimmed = String.trim_leading(line)

    cond do
      not String.starts_with?(trimmed, ",") ->
        :error

      not String.contains?(trimmed, " (") ->
        :error

      not String.contains?(trimmed, "[") or String.contains?(trimmed, "]") ->
        :error

      true ->
        with {outer_idx, _} <- :binary.match(trimmed, " ("),
             outer when is_binary(outer) <-
               binary_part(trimmed, 0, outer_idx) |> String.trim_trailing(),
             inner_start <-
               binary_part(trimmed, outer_idx + 2, byte_size(trimmed) - outer_idx - 2),
             {inner_idx, _} <- :binary.match(inner_start, " ["),
             inner_head when is_binary(inner_head) <-
               binary_part(inner_start, 0, inner_idx) |> String.trim(),
             first_item when is_binary(first_item) <-
               binary_part(inner_start, inner_idx + 2, byte_size(inner_start) - inner_idx - 2)
               |> String.trim(),
             true <- outer != "" and inner_head != "" and first_item != "" do
          {:ok, indent, outer, inner_head, first_item}
        else
          _ -> :error
        end
    end
  end

  @spec collect_multiline_nested_call(term(), term()) :: term()
  defp collect_multiline_nested_call([], _items), do: :error

  defp collect_multiline_nested_call([line | rest], items) do
    trimmed = String.trim_leading(line)

    cond do
      String.contains?(trimmed, "]") ->
        case :binary.match(trimmed, "]") do
          :nomatch ->
            :error

          {idx, _} ->
            before = binary_part(trimmed, 0, idx) |> String.trim()

            after_part =
              binary_part(trimmed, idx + 1, byte_size(trimmed) - idx - 1) |> String.trim()

            items =
              case before do
                "" ->
                  items

                _ ->
                  item = String.trim_leading(before, ",") |> String.trim()
                  if item == "", do: items, else: items ++ [item]
              end

            if String.ends_with?(after_part, ")") do
              args_text = String.trim_trailing(after_part, ")") |> String.trim()
              trailing_args = split_top_level_space_args(args_text)

              if length(trailing_args) >= 2 do
                {:ok, rest, items, trailing_args}
              else
                :error
              end
            else
              :error
            end
        end

      String.starts_with?(trimmed, ",") ->
        item = String.trim_leading(trimmed, ",") |> String.trim()
        if item == "", do: :error, else: collect_multiline_nested_call(rest, items ++ [item])

      true ->
        :error
    end
  end

  @spec emit_multiline_nested_call(term(), term(), term(), term(), term()) :: term()
  defp emit_multiline_nested_call(indent, outer, inner_head, items, trailing_args) do
    base = String.duplicate(" ", indent)
    inner_base = String.duplicate(" ", indent + 4)
    list_base = String.duplicate(" ", indent + 8)

    list_lines =
      case items do
        [first | rest] ->
          [list_base <> "[ " <> first] ++
            Enum.map(rest, &(list_base <> ", " <> &1)) ++ [list_base <> "]"]
      end

    arg_lines = Enum.map(trailing_args, &(list_base <> &1))

    [base <> outer, inner_base <> "(" <> inner_head] ++
      list_lines ++ arg_lines ++ [inner_base <> ")"]
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

  @spec split_if_then_else(term()) :: term()
  defp split_if_then_else(value) do
    condition_part = String.slice(value, 3, String.length(value) - 3)

    with {:ok, condition, after_then} <- split_top_level_keyword(condition_part, " then "),
         {:ok, then_expr, else_expr} <- split_top_level_keyword(after_then, " else ") do
      {:ok, condition, then_expr, else_expr}
    else
      _ -> :error
    end
  end

  @spec split_top_level_keyword(term(), term()) :: term()
  defp split_top_level_keyword(value, keyword) when is_binary(value) and is_binary(keyword) do
    case top_level_keyword_index(value, keyword) do
      nil ->
        :error

      idx ->
        {
          :ok,
          binary_part(value, 0, idx),
          binary_part(
            value,
            idx + byte_size(keyword),
            byte_size(value) - idx - byte_size(keyword)
          )
        }
    end
  end

  @spec expand_binding_line_after_let(term(), term()) :: term()
  defp expand_binding_line_after_let(trimmed, let_indent)
       when is_binary(trimmed) and is_integer(let_indent) do
    case split_top_level_in(trimmed) do
      {binding, expression} ->
        binding = String.trim(binding)
        expression = String.trim(expression)

        if binding == "" or expression == "" or not String.contains?(binding, "=") do
          :no_change
        else
          binding_lines = render_binding_lines(binding, let_indent + 4)
          expression_lines = expand_expression_tail(expression, let_indent)

          {:expanded,
           binding_lines ++
             [String.duplicate(" ", let_indent) <> "in"] ++
             expression_lines}
        end

      :error ->
        :no_change
    end
  end

  @spec expand_inline_let_expression(term(), term()) :: term()
  defp expand_inline_let_expression(trimmed, indent)
       when is_binary(trimmed) and is_integer(indent) do
    rest = String.slice(trimmed, 4, String.length(trimmed) - 4) |> String.trim_leading()

    case split_top_level_in(rest) do
      {binding, expression} ->
        binding = String.trim(binding)
        expression = String.trim(expression)

        if binding == "" or not String.contains?(binding, "=") do
          :no_change
        else
          binding_lines = render_binding_lines(binding, indent + 4)

          if expression == "" do
            {:expanded,
             [String.duplicate(" ", indent) <> "let"] ++
               binding_lines ++ [String.duplicate(" ", indent) <> "in"]}
          else
            expression_lines = expand_expression_tail(expression, indent)

            {:expanded,
             ([String.duplicate(" ", indent) <> "let"] ++
                binding_lines ++ [String.duplicate(" ", indent) <> "in"]) ++ expression_lines}
          end
        end

      :error ->
        :no_change
    end
  end

  @spec expand_expression_tail(term(), term()) :: term()
  defp expand_expression_tail(expression, indent) do
    case expand_inline_let_expression(expression, indent) do
      {:expanded, lines} -> lines
      :no_change -> [String.duplicate(" ", indent) <> expression]
    end
  end

  @spec render_binding_lines(term(), term()) :: term()
  defp render_binding_lines(binding, indent) do
    case split_top_level_equals(binding) do
      {lhs, rhs} ->
        lhs = String.trim(lhs)
        rhs = String.trim(rhs)

        if lhs == "" or rhs == "" do
          [String.duplicate(" ", indent) <> binding]
        else
          [
            String.duplicate(" ", indent) <> lhs <> " =",
            String.duplicate(" ", indent + 4) <> rhs
          ]
        end

      :error ->
        [String.duplicate(" ", indent) <> binding]
    end
  end

  @spec split_top_level_equals(term()) :: term()
  defp split_top_level_equals(binding) do
    case top_level_keyword_index(binding, "=") do
      nil ->
        :error

      idx ->
        {
          binary_part(binding, 0, idx),
          binary_part(binding, idx + 1, byte_size(binding) - idx - 1)
        }
    end
  end

  @spec split_top_level_in(term()) :: term()
  defp split_top_level_in(value) when is_binary(value) do
    case top_level_keyword_index(value, " in ") do
      nil ->
        case top_level_keyword_index(value, " in") do
          nil ->
            :error

          idx ->
            if idx + 3 == byte_size(value) do
              {binary_part(value, 0, idx), ""}
            else
              :error
            end
        end

      idx ->
        {
          binary_part(value, 0, idx),
          binary_part(value, idx + 4, byte_size(value) - idx - 4)
        }
    end
  end

  @spec top_level_keyword_index(term(), term()) :: term()
  defp top_level_keyword_index(value, keyword) do
    do_top_level_keyword_index(value, keyword, [], false, false, 0)
  end

  @spec do_top_level_keyword_index(term(), term(), term(), term(), term(), term()) :: term()
  defp do_top_level_keyword_index("", _keyword, _stack, _in_string, _escape_next, _idx), do: nil

  defp do_top_level_keyword_index(
         <<char::utf8, rest::binary>> = full,
         keyword,
         stack,
         in_string,
         escape_next,
         idx
       ) do
    cond do
      escape_next ->
        do_top_level_keyword_index(rest, keyword, stack, in_string, false, idx + 1)

      in_string and char == ?\\ ->
        do_top_level_keyword_index(rest, keyword, stack, in_string, true, idx + 1)

      char == ?" ->
        do_top_level_keyword_index(rest, keyword, stack, not in_string, false, idx + 1)

      in_string ->
        do_top_level_keyword_index(rest, keyword, stack, in_string, false, idx + 1)

      char in [?(, ?[, ?{] ->
        do_top_level_keyword_index(rest, keyword, [char | stack], false, false, idx + 1)

      char in [?), ?], ?}] ->
        do_top_level_keyword_index(rest, keyword, pop_stack(stack, char), false, false, idx + 1)

      stack == [] and top_level_keyword_match?(full, keyword, char) ->
        idx

      true ->
        do_top_level_keyword_index(rest, keyword, stack, false, false, idx + 1)
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

  @spec top_level_keyword_match?(term(), term(), term()) :: term()
  defp top_level_keyword_match?(full, keyword, char)
       when is_binary(keyword) and byte_size(keyword) == 1 do
    <<single::utf8>> = keyword
    char == single and not String.starts_with?(full, "==")
  end

  defp top_level_keyword_match?(full, keyword, _char) when is_binary(keyword) do
    String.starts_with?(full, keyword)
  end

  @spec collapse_spaces(term()) :: term()
  defp collapse_spaces(value) do
    value
    |> String.graphemes()
    |> Enum.reduce({[], false}, fn char, {acc, in_ws?} ->
      if char in [" ", "\t"] do
        if in_ws? do
          {acc, true}
        else
          {[" " | acc], true}
        end
      else
        {[char | acc], false}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.join()
    |> String.trim()
  end

  @spec tuple_open_indent(term()) :: term()
  defp tuple_open_indent(line) do
    if not starts_with_trimmed?(line, "(") do
      nil
    else
      open_cols = top_level_char_columns(line, ?()
      close_cols = top_level_char_columns(line, ?))

      if length(open_cols) > length(close_cols) do
        (List.last(open_cols) || 1) - 1
      else
        nil
      end
    end
  end

  @spec starts_with_trimmed?(term(), term()) :: term()
  defp starts_with_trimmed?(line, marker),
    do: String.starts_with?(String.trim_leading(line), marker)

  @spec top_level_char_columns(term(), term()) :: term()
  defp top_level_char_columns(line, char_code) do
    line
    |> scan_top_level_for_char([], false, false, 1, char_code, [])
    |> Enum.reverse()
  end

  @spec scan_top_level_for_char(term(), term(), term(), term(), term(), term(), term()) :: term()
  defp scan_top_level_for_char("", _stack, _in_string, _escape_next, _col, _char_code, acc),
    do: acc

  defp scan_top_level_for_char(
         <<char::utf8, rest::binary>>,
         stack,
         in_string,
         escape_next,
         col,
         char_code,
         acc
       ) do
    cond do
      escape_next ->
        scan_top_level_for_char(rest, stack, in_string, false, col + 1, char_code, acc)

      in_string and char == ?\\ ->
        scan_top_level_for_char(rest, stack, in_string, true, col + 1, char_code, acc)

      char == ?" ->
        scan_top_level_for_char(rest, stack, not in_string, false, col + 1, char_code, acc)

      in_string ->
        scan_top_level_for_char(rest, stack, in_string, false, col + 1, char_code, acc)

      char in [?(, ?[, ?{] ->
        next_stack = [char | stack]
        next_acc = if char == char_code and stack == [], do: [col | acc], else: acc
        scan_top_level_for_char(rest, next_stack, false, false, col + 1, char_code, next_acc)

      char in [?), ?], ?}] ->
        next_acc = if char == char_code and stack == [], do: [col | acc], else: acc

        scan_top_level_for_char(
          rest,
          pop_stack(stack, char),
          false,
          false,
          col + 1,
          char_code,
          next_acc
        )

      stack == [] and char == char_code ->
        scan_top_level_for_char(rest, stack, false, false, col + 1, char_code, [col | acc])

      true ->
        scan_top_level_for_char(rest, stack, false, false, col + 1, char_code, acc)
    end
  end

  @spec leading_indent(term()) :: term()
  defp leading_indent(line) do
    String.length(line) - String.length(String.trim_leading(line))
  end

  @spec opens_record_tuple_pair?(term()) :: term()
  defp opens_record_tuple_pair?(line) do
    trimmed = String.trim_leading(line)

    String.starts_with?(trimmed, "(") and String.contains?(trimmed, "{") and
      not String.contains?(trimmed, ")")
  end
end
