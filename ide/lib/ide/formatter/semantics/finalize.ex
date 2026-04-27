defmodule Ide.Formatter.Semantics.Finalize do
  @moduledoc false

  @spec finalize(String.t()) :: String.t()
  def finalize(source) when is_binary(source) do
    source
    |> String.split("\n", trim: false)
    |> ensure_import_doc_gap()
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 == ""))
    |> Enum.reverse()
    |> Enum.join("\n")
    |> ensure_terminal_newline()
  end

  @spec ensure_terminal_newline(term()) :: term()
  defp ensure_terminal_newline(""), do: "\n"

  defp ensure_terminal_newline(value),
    do: if(String.ends_with?(value, "\n"), do: value, else: value <> "\n")

  @spec ensure_import_doc_gap(term()) :: term()
  defp ensure_import_doc_gap(lines) when is_list(lines) do
    Enum.reduce(lines, [], fn line, acc ->
      trimmed = String.trim_leading(line)
      at_top_level = leading_indent(line) == 0

      if at_top_level and String.starts_with?(trimmed, "{-|") do
        case last_non_empty(acc) do
          prev when is_binary(prev) ->
            if String.starts_with?(String.trim_leading(prev), "import ") do
              trailing_blanks = count_trailing_blank_lines(acc)
              needed = max(2 - trailing_blanks, 0)
              acc ++ List.duplicate("", needed) ++ [line]
            else
              acc ++ [line]
            end

          _ ->
            acc ++ [line]
        end
      else
        acc ++ [line]
      end
    end)
  end

  @spec last_non_empty(term()) :: term()
  defp last_non_empty(lines) when is_list(lines) do
    lines
    |> Enum.reverse()
    |> Enum.find(&(String.trim(&1) != ""))
  end

  @spec leading_indent(term()) :: term()
  defp leading_indent(line) do
    String.length(line) - String.length(String.trim_leading(line))
  end

  @spec count_trailing_blank_lines(term()) :: term()
  defp count_trailing_blank_lines(lines) when is_list(lines) do
    lines
    |> Enum.reverse()
    |> Enum.take_while(&(&1 == ""))
    |> length()
  end
end
