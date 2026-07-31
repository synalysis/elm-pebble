defmodule ElmEx.Frontend.Layout do
  @moduledoc """
  Shared layout constants and helpers for parse and print.

  Used by `ElmEx.Frontend.ExprLayoutLexer` (significant indentation while
  tokenizing), `ElmEx.Frontend.LayoutRules` (shared binding/arm heuristics),
  `ElmEx.Frontend.LayoutEnter` (Enter- and Tab-key indentation in the IDE), and
  `ElmEx.Frontend.Pretty` (emitting Elm-shaped layout).
  """
  @default_indent_step 4

  @doc "Spaces per indentation level in generated Elm source."
  @spec indent_step() :: pos_integer()

  def indent_step, do: @default_indent_step

  @doc "Indent string for a given nesting level (0 → empty)."
  @spec spaces(non_neg_integer()) :: String.t()
  def spaces(level) when is_integer(level) and level >= 0 do
    String.duplicate(" ", level * @default_indent_step)
  end

  @doc "Prefix each line of `text` with `spaces(level)`."
  @spec indent_lines(String.t(), non_neg_integer()) :: String.t()
  def indent_lines(text, level) when is_binary(text) and is_integer(level) and level >= 0 do
    pad = spaces(level)

    text
    |> String.split("\n")
    |> Enum.map(fn
      "" -> ""
      line -> pad <> line
    end)
    |> Enum.join("\n")
  end

  @doc "Width of a tab character when counting physical indentation."
  @spec tab_width(String.t()) :: pos_integer()
  def tab_width("\t"), do: @default_indent_step
  def tab_width(_), do: 1

  @doc """
  Subtract the minimum leading whitespace from every non-blank line.

  Keeps relative indentation when a snippet is pasted or read from a heredoc
  with uniform extra leading spaces; pairs with trim that only removes blank
  lines, not the first line's indent in isolation.
  """
  @spec dedent_uniform_leading_whitespace(String.t()) :: String.t()
  def dedent_uniform_leading_whitespace(source) when is_binary(source) do
    lines = String.split(source, "\n")

    min_indent =
      lines
      |> Enum.reject(&(String.trim(&1) == ""))
      |> Enum.map(&leading_whitespace_count/1)
      |> case do
        [] -> 0
        counts -> Enum.min(counts)
      end

    if min_indent > 0 do
      lines
      |> Enum.map(fn line ->
        if String.trim(line) == "" do
          line
        else
          String.slice(line, min_indent..-1//1)
        end
      end)
      |> Enum.join("\n")
    else
      source
    end
  end

  @spec leading_whitespace_count(String.t()) :: non_neg_integer()
  defp leading_whitespace_count(line) do
    line
    |> String.graphemes()
    |> Enum.take_while(&(&1 in [" ", "\t"]))
    |> length()
  end
end
