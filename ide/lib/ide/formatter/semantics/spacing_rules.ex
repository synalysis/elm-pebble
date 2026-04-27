defmodule Ide.Formatter.Semantics.SpacingRules do
  @moduledoc false
  alias Ide.Formatter.Semantics.TextOps

  @spec comma_char?(String.t()) :: boolean()
  def comma_char?(char) when is_binary(char), do: char == ","

  @spec normalize_comma_spacing(String.t(), [map()] | nil) :: String.t()
  def normalize_comma_spacing(source, tokens \\ nil)

  def normalize_comma_spacing(source, tokens) when is_binary(source) and is_list(tokens) do
    comma_columns_by_line =
      tokens
      |> Enum.filter(fn token ->
        token[:text] == "," and is_integer(token[:line]) and is_integer(token[:column])
      end)
      |> Enum.group_by(& &1.line, & &1.column)
      |> Map.new(fn {line, cols} -> {line, cols |> Enum.uniq() |> Enum.sort(:desc)} end)

    {normalized_rev, _in_block_comment} =
      source
      |> String.split("\n", trim: false)
      |> Enum.with_index(1)
      |> Enum.reduce({[], false}, fn {line, line_no}, {acc, in_block_comment} ->
        cols = Map.get(comma_columns_by_line, line_no, [])

        next_line =
          line
          |> then(fn current ->
            if in_block_comment or cols == [] do
              current
            else
              Enum.reduce(cols, current, &normalize_comma_at_column(&2, &1))
            end
          end)
          |> normalize_comma_spacing_line(in_block_comment)

        {[next_line | acc], block_comment_state_after(line, in_block_comment)}
      end)

    normalized_rev
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  def normalize_comma_spacing(source, _tokens) when is_binary(source) do
    {normalized_rev, _in_block_comment} =
      source
      |> String.split("\n", trim: false)
      |> Enum.reduce({[], false}, fn line, {acc, in_block_comment} ->
        next_line = normalize_comma_spacing_line(line, in_block_comment)
        {[next_line | acc], block_comment_state_after(line, in_block_comment)}
      end)

    normalized_rev
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  @spec normalize_comma_spacing_line(term(), term()) :: term()
  defp normalize_comma_spacing_line(line, in_block_comment) do
    trimmed = String.trim_leading(line)

    if in_block_comment or String.starts_with?(trimmed, "--") or String.contains?(trimmed, "{-") or
         (not String.starts_with?(trimmed, ",") and String.contains?(line, "[") and
            String.contains?(line, "]")) do
      line
    else
      TextOps.normalize_comma_spacing(line)
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

  @spec normalize_comma_at_column(term(), term()) :: term()
  defp normalize_comma_at_column(line, column) when is_binary(line) and is_integer(column) do
    comma_idx = max(column - 1, 0)
    safe_idx = min(comma_idx, String.length(line))

    case locate_comma_index(line, safe_idx) do
      {:ok, actual_idx} ->
        before = String.slice(line, 0, actual_idx)
        after_comma = String.slice(line, actual_idx + 1, String.length(line))

        before = TextOps.trim_trailing_horizontal(before)
        after_no_ws = String.trim_leading(after_comma, " \t")
        next_char = String.at(after_no_ws, 0)

        needs_space_after? =
          is_binary(next_char) and next_char not in [",", ")", "]", "}"]

        spacer = if needs_space_after?, do: " ", else: ""
        before <> "," <> spacer <> after_no_ws

      :nomatch ->
        line
    end
  end

  @spec locate_comma_index(term(), term()) :: term()
  defp locate_comma_index(line, idx) do
    if String.at(line, idx) == "," do
      {:ok, idx}
    else
      tail = String.slice(line, idx, String.length(line))

      case :binary.match(tail, ",") do
        {rel, _len} -> {:ok, idx + rel}
        :nomatch -> :nomatch
      end
    end
  end
end
