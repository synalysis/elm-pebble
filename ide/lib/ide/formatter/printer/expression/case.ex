defmodule Ide.Formatter.Printer.Expression.Case do
  @moduledoc false
  alias Ide.Formatter.Semantics.Rules

  @spec normalize_arrow_indentation(String.t()) :: String.t()
  def normalize_arrow_indentation(source) when is_binary(source) do
    source
    |> String.split("\n", trim: false)
    |> do_normalize_case_arrow_indentation(nil, [])
    |> Enum.join("\n")
    |> normalize_branch_head_spacing()
  end

  @spec do_normalize_case_arrow_indentation(term(), term(), term()) :: term()
  defp do_normalize_case_arrow_indentation([], _prev_indent, acc), do: Enum.reverse(acc)

  defp do_normalize_case_arrow_indentation([line | rest], prev_indent, acc) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        do_normalize_case_arrow_indentation(rest, prev_indent, [line | acc])

      true ->
        case parse_arrow_only_line(line) do
          {:ok, current_indent, trailing} ->
            indent_width = Rules.indent_width()

            if is_integer(prev_indent) and current_indent == prev_indent + indent_width do
              {shifted_followers, remaining} =
                shift_case_branch_followers(rest, current_indent + indent_width, indent_width, [])

              normalized_arrow = String.duplicate(" ", prev_indent) <> "->" <> trailing
              chunk = [normalized_arrow | shifted_followers]

              do_normalize_case_arrow_indentation(
                remaining,
                prev_indent,
                Enum.reverse(chunk) ++ acc
              )
            else
              do_normalize_case_arrow_indentation(rest, leading_indent(line), [line | acc])
            end

          :error ->
            do_normalize_case_arrow_indentation(rest, leading_indent(line), [line | acc])
        end
    end
  end

  @spec shift_case_branch_followers(term(), term(), term(), term()) :: term()
  defp shift_case_branch_followers([], _threshold_indent, _delta, acc),
    do: {Enum.reverse(acc), []}

  defp shift_case_branch_followers([line | rest] = all, threshold_indent, delta, acc) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        {Enum.reverse(acc), all}

      leading_indent(line) >= threshold_indent ->
        shifted =
          String.duplicate(" ", leading_indent(line) - delta) <>
            String.trim_leading(line)

        shift_case_branch_followers(rest, threshold_indent, delta, [shifted | acc])

      true ->
        {Enum.reverse(acc), all}
    end
  end

  @spec parse_arrow_only_line(term()) :: term()
  defp parse_arrow_only_line(line) do
    indent = leading_indent(line)
    trimmed = String.trim_leading(line)

    if String.starts_with?(trimmed, "->") do
      tail = String.slice(trimmed, 2, String.length(trimmed))

      if String.trim(tail) == "" do
        {:ok, indent, tail}
      else
        :error
      end
    else
      :error
    end
  end

  @spec leading_indent(term()) :: term()
  defp leading_indent(line) do
    String.length(line) - String.length(String.trim_leading(line))
  end

  @spec normalize_branch_head_spacing(term()) :: term()
  defp normalize_branch_head_spacing(source) do
    {lines_rev, _state} =
      source
      |> String.split("\n", trim: false)
      |> Enum.reduce(
        {[], %{in_case: false, case_indent: nil, pending_branch_body_indent: nil}},
        fn line, {acc, state} ->
          trimmed = String.trim(line)
          indent = leading_indent(line)

          cond do
            case_start_line?(line) ->
              {[line | acc],
               %{in_case: true, case_indent: indent, pending_branch_body_indent: nil}}

            state.in_case and trimmed == "" ->
              {[line | acc], state}

            state.in_case and exits_case_block?(line, state.case_indent) ->
              {[line | acc], %{in_case: false, case_indent: nil, pending_branch_body_indent: nil}}

            state.in_case and case_branch_line_candidate?(line, state.case_indent) ->
              normalized = normalize_case_branch_line(line, state.case_indent)

              pending =
                if String.ends_with?(normalized, "->"), do: state.case_indent + 8, else: nil

              {[normalized | acc], %{state | pending_branch_body_indent: pending}}

            state.in_case and is_integer(state.pending_branch_body_indent) and
              not comment_line?(line) and
                indent < state.pending_branch_body_indent ->
              normalized =
                String.duplicate(" ", state.pending_branch_body_indent) <>
                  String.trim_leading(line)

              {[normalized | acc], %{state | pending_branch_body_indent: nil}}

            true ->
              {[line | acc], %{state | pending_branch_body_indent: nil}}
          end
        end
      )

    lines_rev
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  @spec case_start_line?(term()) :: term()
  defp case_start_line?(line) do
    trimmed = String.trim_leading(line)
    String.starts_with?(trimmed, "case ") and String.ends_with?(trimmed, " of")
  end

  @spec exits_case_block?(term(), term()) :: term()
  defp exits_case_block?(line, case_indent) when is_integer(case_indent) do
    trimmed = String.trim(line)
    leading_indent(line) <= case_indent and trimmed != "" and not comment_line?(line)
  end

  defp exits_case_block?(_line, _case_indent), do: false

  @spec case_branch_line_candidate?(term(), term()) :: term()
  defp case_branch_line_candidate?(line, case_indent) when is_integer(case_indent) do
    indent = leading_indent(line)
    trimmed = String.trim_leading(line)

    indent <= case_indent + Rules.indent_width() + 2 and
      String.contains?(trimmed, "->") and not String.starts_with?(trimmed, "case ") and
      not String.starts_with?(trimmed, "->") and not comment_line?(line)
  end

  defp case_branch_line_candidate?(_line, _case_indent), do: false

  @spec normalize_case_branch_line(term(), term()) :: term()
  defp normalize_case_branch_line(line, case_indent) do
    trimmed = String.trim_leading(line)
    branch_indent = case_indent + Rules.indent_width()

    case split_once(trimmed, "->") do
      {lhs, rhs} ->
        normalized_lhs = collapse_spaces(lhs)
        normalized_rhs = String.trim_leading(rhs)

        if normalized_rhs == "" do
          String.duplicate(" ", branch_indent) <> normalized_lhs <> " ->"
        else
          String.duplicate(" ", branch_indent) <> normalized_lhs <> " -> " <> normalized_rhs
        end

      :error ->
        line
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

  @spec comment_line?(term()) :: term()
  defp comment_line?(line) do
    trimmed = String.trim_leading(line)
    String.starts_with?(trimmed, "--") or String.starts_with?(trimmed, "{-")
  end
end
