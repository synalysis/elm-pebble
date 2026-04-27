defmodule Ide.Formatter.Semantics.TextOps do
  @moduledoc false

  @spec trim_trailing_horizontal(String.t()) :: String.t()
  def trim_trailing_horizontal(value) when is_binary(value) do
    value
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.drop_while(&horizontal_ws?/1)
    |> Enum.reverse()
    |> Enum.join()
  end

  @spec normalize_comma_spacing(String.t()) :: String.t()
  def normalize_comma_spacing(value) when is_binary(value) do
    do_normalize_comma_spacing(String.graphemes(value), [], false, false)
    |> Enum.reverse()
    |> Enum.join()
  end

  @spec normalize_colon_spacing(String.t()) :: String.t()
  def normalize_colon_spacing(value) when is_binary(value) do
    chars = String.graphemes(value)

    do_normalize_colon_spacing(chars, [], nil)
    |> Enum.reverse()
    |> Enum.join()
  end

  @spec collapse_horizontal_runs(String.t()) :: String.t()
  def collapse_horizontal_runs(value) when is_binary(value) do
    value
    |> String.graphemes()
    |> Enum.reduce({[], false}, fn char, {acc, in_ws?} ->
      if horizontal_ws?(char) do
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
  end

  @spec do_normalize_comma_spacing(term(), term(), term(), term()) :: term()
  defp do_normalize_comma_spacing([], acc, _in_string, _escape_next), do: acc

  defp do_normalize_comma_spacing([char | rest], acc, in_string, escape_next)
       when in_string and escape_next do
    do_normalize_comma_spacing(rest, [char | acc], in_string, false)
  end

  defp do_normalize_comma_spacing(["\\" | rest], acc, true, false) do
    do_normalize_comma_spacing(rest, ["\\" | acc], true, true)
  end

  defp do_normalize_comma_spacing(["\"" | rest], acc, in_string, false) do
    do_normalize_comma_spacing(rest, ["\"" | acc], not in_string, false)
  end

  defp do_normalize_comma_spacing(["," | rest], acc, false, false) do
    acc = trim_trailing_horizontal_before_delimiter(acc)
    {remaining, next_char} = drop_leading_horizontal(rest)
    needs_space? = is_binary(next_char) and next_char not in [",", ")", "]", "}"]
    spacer = if needs_space?, do: [" "], else: []
    do_normalize_comma_spacing(remaining, Enum.reverse(spacer) ++ ["," | acc], false, false)
  end

  defp do_normalize_comma_spacing([char | rest], acc, in_string, escape_next),
    do: do_normalize_comma_spacing(rest, [char | acc], in_string, escape_next)

  @spec do_normalize_colon_spacing(term(), term(), term()) :: term()
  defp do_normalize_colon_spacing([], acc, _next), do: acc

  defp do_normalize_colon_spacing([":" | rest], acc, prev_char) do
    next_char = List.first(rest)

    if prev_char == ":" or next_char == ":" do
      do_normalize_colon_spacing(rest, [":" | acc], ":")
    else
      acc = trim_trailing_horizontal_before_delimiter(acc)
      {remaining, _next_after_spaces} = drop_leading_horizontal(rest)
      do_normalize_colon_spacing(remaining, [" ", ":", " " | acc], ":")
    end
  end

  defp do_normalize_colon_spacing([char | rest], acc, _prev_char),
    do: do_normalize_colon_spacing(rest, [char | acc], char)

  @spec trim_trailing_horizontal_before_delimiter(term()) :: term()
  defp trim_trailing_horizontal_before_delimiter(acc) do
    trimmed = Enum.drop_while(acc, &horizontal_ws?/1)
    if trimmed == [], do: acc, else: trimmed
  end

  @spec drop_leading_horizontal(term()) :: term()
  defp drop_leading_horizontal(chars) do
    remaining = Enum.drop_while(chars, &horizontal_ws?/1)
    {remaining, List.first(remaining)}
  end

  @spec horizontal_ws?(term()) :: term()
  defp horizontal_ws?(value), do: value in [" ", "\t"]
end
