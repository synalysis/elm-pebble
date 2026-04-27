defmodule Ide.Formatter.Semantics.Layout do
  @moduledoc false

  @spec normalize_layout(String.t()) :: String.t()
  def normalize_layout(source) when is_binary(source) do
    source
    |> String.split("\n", trim: false)
    |> normalize_line_whitespace(false, [])
    |> Enum.reverse()
    |> Enum.join("\n")
    |> ensure_terminal_newline()
  end

  @spec ensure_terminal_newline(term()) :: term()
  defp ensure_terminal_newline(""), do: "\n"

  defp ensure_terminal_newline(value) do
    if String.ends_with?(value, "\n"), do: value, else: value <> "\n"
  end

  @spec normalize_line_whitespace(term(), term(), term()) :: term()
  defp normalize_line_whitespace([], _in_multiline, acc), do: acc

  defp normalize_line_whitespace([line | rest], in_multiline, acc) do
    delimiter_count = multiline_delimiter_count(line)
    touches_multiline = in_multiline or delimiter_count > 0

    normalized_line =
      if touches_multiline do
        line
      else
        String.trim_trailing(line)
      end

    next_in_multiline = if rem(delimiter_count, 2) == 1, do: not in_multiline, else: in_multiline
    normalize_line_whitespace(rest, next_in_multiline, [normalized_line | acc])
  end

  @spec multiline_delimiter_count(term()) :: term()
  defp multiline_delimiter_count(line) do
    Regex.scan(~r/"""/, line) |> length()
  end
end
