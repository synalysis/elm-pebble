defmodule Ide.Formatter.Printer.Pattern do
  @moduledoc false

  @spec normalize_case_constructor_parens(String.t()) :: String.t()
  def normalize_case_constructor_parens(source) when is_binary(source) do
    source
    |> String.split("\n", trim: false)
    |> Enum.map(&normalize_case_constructor_line/1)
    |> Enum.join("\n")
  end

  @spec normalize_nested_as_pattern_parens(String.t()) :: String.t()
  def normalize_nested_as_pattern_parens(source) when is_binary(source) do
    do_normalize_nested_as_pattern_parens(source)
  end

  @spec normalize_case_constructor_line(term()) :: term()
  defp normalize_case_constructor_line(line) do
    trimmed = String.trim_leading(line)

    if String.contains?(trimmed, "->") do
      case split_once(trimmed, "->") do
        {before_arrow, after_arrow} ->
          left = String.trim_trailing(before_arrow)

          case split_last_once(left, " ") do
            {head, tail} ->
              tail_trimmed = String.trim(tail)

              if String.starts_with?(tail_trimmed, "(") and String.ends_with?(tail_trimmed, ")") do
                inner = tail_trimmed |> String.trim_leading("(") |> String.trim_trailing(")")

                if uppercase_path?(String.trim(inner)) do
                  leading_spaces(line) <>
                    String.trim_trailing(head) <>
                    " " <>
                    String.trim(inner) <>
                    " ->" <>
                    String.trim_leading(after_arrow)
                else
                  line
                end
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

  @spec do_normalize_nested_as_pattern_parens(term()) :: term()
  defp do_normalize_nested_as_pattern_parens(source) do
    case :binary.match(source, "((") do
      :nomatch ->
        source

      {idx, _len} ->
        prefix = binary_part(source, 0, idx)
        rest = binary_part(source, idx, byte_size(source) - idx)

        case consume_nested_as_pattern(rest) do
          {:ok, replacement, consumed} ->
            suffix = binary_part(rest, consumed, byte_size(rest) - consumed)
            do_normalize_nested_as_pattern_parens(prefix <> replacement <> suffix)

          :error ->
            first = binary_part(rest, 0, 1)
            remaining = binary_part(rest, 1, byte_size(rest) - 1)
            prefix <> first <> do_normalize_nested_as_pattern_parens(remaining)
        end
    end
  end

  @spec consume_nested_as_pattern(term()) :: term()
  defp consume_nested_as_pattern("((" <> rest) do
    with {:ok, ctor, after_ctor} <- take_until(rest, ")"),
         true <- uppercase_path?(String.trim(ctor)),
         true <- String.starts_with?(after_ctor, " as "),
         after_as <- String.slice(after_ctor, 4, String.length(after_ctor) - 4),
         {:ok, var, after_var} <- take_identifier(after_as),
         true <- String.starts_with?(after_var, ")") do
      consumed = 2 + String.length(ctor) + 1 + 4 + String.length(var) + 1
      replacement = "(#{String.trim(ctor)} as #{var})"
      {:ok, replacement, consumed}
    else
      _ -> :error
    end
  end

  defp consume_nested_as_pattern(_), do: :error

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

  @spec split_last_once(term(), term()) :: term()
  defp split_last_once(value, delimiter) do
    case :binary.matches(value, delimiter) do
      [] ->
        :error

      matches ->
        {idx, len} = List.last(matches)

        {
          binary_part(value, 0, idx),
          binary_part(value, idx + len, byte_size(value) - idx - len)
        }
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

  @spec take_identifier(term()) :: term()
  defp take_identifier(value) do
    chars = String.graphemes(value)
    {name_chars, remaining} = Enum.split_while(chars, &as_var_char?/1)

    case name_chars do
      [first | _] when first >= "a" and first <= "z" ->
        {:ok, Enum.join(name_chars), Enum.join(remaining)}

      _ ->
        :error
    end
  end

  @spec as_var_char?(term()) :: term()
  defp as_var_char?(char) when is_binary(char) do
    case String.to_charlist(char) do
      [c] -> c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_
      _ -> false
    end
  end

  @spec uppercase_path?(term()) :: term()
  defp uppercase_path?(value) do
    value
    |> String.split(".", trim: true)
    |> case do
      [] ->
        false

      segments ->
        Enum.all?(segments, fn segment ->
          case String.to_charlist(segment) do
            [first | rest] ->
              first in ?A..?Z and Enum.all?(rest, &identifier_char?/1)

            _ ->
              false
          end
        end)
    end
  end

  @spec identifier_char?(term()) :: term()
  defp identifier_char?(c), do: c in ?A..?Z or c in ?a..?z or c in ?0..?9 or c in [?_, ?.]

  @spec leading_spaces(term()) :: term()
  defp leading_spaces(line) do
    String.slice(line, 0, leading_indent(line))
  end

  @spec leading_indent(term()) :: term()
  defp leading_indent(line) do
    String.length(line) - String.length(String.trim_leading(line))
  end
end
