defmodule Ide.Formatter.Printer.TypeDecl do
  @moduledoc false
  alias Ide.Formatter.Semantics.Rules

  @spec normalize_alias_head_spacing(String.t()) :: String.t()
  def normalize_alias_head_spacing(source) when is_binary(source) do
    source
    |> String.split("\n", trim: false)
    |> Enum.map(&normalize_alias_head_line/1)
    |> Enum.join("\n")
  end

  @spec normalize_union_constructor_alignment(String.t()) :: String.t()
  def normalize_union_constructor_alignment(source) when is_binary(source) do
    lines = String.split(source, "\n", trim: false)

    normalized_rev =
      normalize_union_lines(
        lines,
        %{in_type_decl: false, declaration_indent: 0, pipe_indent: nil, pending_blanks: 0},
        []
      )

    normalized_rev
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  @spec normalize_union_lines(term(), term(), term()) :: term()
  defp normalize_union_lines([], state, acc) do
    emit_blanks(acc, state.pending_blanks)
  end

  defp normalize_union_lines([line | rest], state, acc) do
    trimmed = String.trim_leading(line)

    cond do
      type_declaration_line?(line) and not String.contains?(line, "type alias") ->
        next_state = %{
          in_type_decl: true,
          declaration_indent: leading_indent(line),
          pipe_indent: nil,
          pending_blanks: 0
        }

        normalize_union_lines(rest, next_state, [line | emit_blanks(acc, state.pending_blanks)])

      state.in_type_decl and starts_with_trimmed?(line, "=") ->
        indent = state.declaration_indent + Rules.indent_width()
        normalized = normalize_union_constructor_line(line, indent, "=")
        next_state = %{state | pipe_indent: indent, pending_blanks: 0}
        normalize_union_lines(rest, next_state, [normalized | acc])

      state.in_type_decl and is_integer(state.pipe_indent) and starts_with_trimmed?(line, "|") ->
        normalized = normalize_union_constructor_line(line, state.pipe_indent, "|")
        next_state = %{state | pending_blanks: 0}
        normalize_union_lines(rest, next_state, [normalized | acc])

      state.in_type_decl and is_integer(state.pipe_indent) and
          leading_indent(line) > state.pipe_indent ->
        normalize_union_lines(rest, %{state | pending_blanks: 0}, [line | acc])

      state.in_type_decl and is_integer(state.pipe_indent) and starts_with_trimmed?(line, "--") and
          leading_indent(line) > state.pipe_indent ->
        normalize_union_lines(rest, %{state | pending_blanks: 0}, [line | acc])

      state.in_type_decl and trimmed == "" ->
        next_state = %{state | pending_blanks: state.pending_blanks + 1}
        normalize_union_lines(rest, next_state, acc)

      state.in_type_decl ->
        separator_blanks = max(state.pending_blanks, 1)

        acc =
          acc
          |> emit_blanks(separator_blanks)
          |> then(&[line | &1])

        next_state = %{
          in_type_decl: false,
          declaration_indent: 0,
          pipe_indent: nil,
          pending_blanks: 0
        }

        normalize_union_lines(rest, next_state, acc)

      true ->
        normalize_union_lines(rest, %{state | pending_blanks: 0}, [line | acc])
    end
  end

  @spec emit_blanks(term(), term()) :: term()
  defp emit_blanks(acc, 0), do: acc
  defp emit_blanks(acc, n) when n > 0, do: emit_blanks(["" | acc], n - 1)

  @spec normalize_union_constructor_line(term(), term(), term()) :: term()
  defp normalize_union_constructor_line(line, indent, marker) do
    trimmed = String.trim_leading(line)

    if String.starts_with?(trimmed, marker) do
      rhs =
        trimmed
        |> String.slice(String.length(marker), String.length(trimmed))
        |> String.trim_leading()

      base_line = String.duplicate(" ", indent) <> marker <> " "

      case split_top_level_pipes(rhs) do
        [single] ->
          base_line <> collapse_spaces(single)

        [first | rest] ->
          continuation =
            rest
            |> Enum.map(fn segment ->
              String.duplicate(" ", indent) <> "| " <> collapse_spaces(segment)
            end)
            |> Enum.join("\n")

          base_line <> collapse_spaces(first) <> "\n" <> continuation

        [] ->
          base_line
      end
    else
      String.duplicate(" ", indent) <> trimmed
    end
  end

  @spec starts_with_trimmed?(term(), term()) :: term()
  defp starts_with_trimmed?(line, marker) when is_binary(marker) do
    String.trim_leading(line) |> String.starts_with?(marker)
  end

  @spec type_declaration_line?(term()) :: term()
  defp type_declaration_line?(line) do
    trimmed = String.trim_leading(line)

    if String.starts_with?(trimmed, "type ") do
      next = String.at(trimmed, 5)

      case next do
        nil -> false
        <<c::utf8>> -> c in ?A..?Z
        _ -> false
      end
    else
      false
    end
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

  @spec split_top_level_pipes(term()) :: term()
  defp split_top_level_pipes(value) when is_binary(value) do
    do_split_top_level_pipes(value, [], "", [], false, false)
  end

  @spec do_split_top_level_pipes(term(), term(), term(), term(), term(), term()) :: term()
  defp do_split_top_level_pipes("", _stack, current, segments, _in_string, _escape_next) do
    normalized = String.trim(current)
    if normalized == "", do: segments, else: segments ++ [normalized]
  end

  defp do_split_top_level_pipes(
         <<char::utf8, rest::binary>>,
         stack,
         current,
         segments,
         in_string,
         escape_next
       ) do
    cond do
      escape_next ->
        do_split_top_level_pipes(
          rest,
          stack,
          current <> <<char::utf8>>,
          segments,
          in_string,
          false
        )

      in_string and char == ?\\ ->
        do_split_top_level_pipes(
          rest,
          stack,
          current <> <<char::utf8>>,
          segments,
          in_string,
          true
        )

      char == ?" ->
        do_split_top_level_pipes(
          rest,
          stack,
          current <> <<char::utf8>>,
          segments,
          not in_string,
          false
        )

      in_string ->
        do_split_top_level_pipes(
          rest,
          stack,
          current <> <<char::utf8>>,
          segments,
          in_string,
          false
        )

      char in [?(, ?[, ?{] ->
        do_split_top_level_pipes(
          rest,
          [char | stack],
          current <> <<char::utf8>>,
          segments,
          false,
          false
        )

      char in [?), ?], ?}] ->
        do_split_top_level_pipes(
          rest,
          pop_stack(stack, char),
          current <> <<char::utf8>>,
          segments,
          false,
          false
        )

      char == ?| and stack == [] ->
        next =
          case String.trim(current) do
            "" -> segments
            value -> segments ++ [value]
          end

        do_split_top_level_pipes(rest, stack, "", next, false, false)

      true ->
        do_split_top_level_pipes(rest, stack, current <> <<char::utf8>>, segments, false, false)
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

  @spec leading_indent(term()) :: term()
  defp leading_indent(line) do
    String.length(line) - String.length(String.trim_leading(line))
  end

  @spec normalize_alias_head_line(term()) :: term()
  defp normalize_alias_head_line(line) do
    trimmed = String.trim_leading(line)

    if String.starts_with?(trimmed, "type alias ") do
      case split_once(trimmed, "=") do
        {lhs, rhs} ->
          indent = String.slice(line, 0, leading_indent(line))
          normalized_lhs = collapse_spaces(lhs)
          normalized_rhs = String.trim_leading(rhs)

          if normalized_rhs == "" do
            indent <> normalized_lhs <> " ="
          else
            indent <> normalized_lhs <> " = " <> normalized_rhs
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
end
