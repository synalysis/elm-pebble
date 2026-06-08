defmodule Elmc.Backend.CCodegen.CSource do
  @moduledoc """
  Formatting and layout helpers for generated C source.

  Emitters should build C fragments with `indent/2` or `format_block/2`, then
  pass assembled translation units through `format/1` before writing files.
  """

  @indent_unit 2

  @spec format(String.t()) :: String.t()
  def format(source) when is_binary(source) do
    source
    |> String.split("\n", trim: false)
    |> format_lines()
    |> collapse_blank_run(1)
    |> Enum.join("\n")
    |> String.trim_trailing()
    |> Kernel.<>("\n")
  end

  @spec indent(String.t(), non_neg_integer()) :: String.t()
  def indent(text, spaces) do
    pad = String.duplicate(" ", spaces)

    text
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      if String.trim(line) == "", do: line, else: pad <> line
    end)
  end

  @spec format_block(String.t(), non_neg_integer()) :: String.t()
  def format_block(code, base_indent \\ 2) when is_binary(code) do
    base_pad = String.duplicate(" ", base_indent)

    code
    |> String.split("\n", trim: false)
    |> Enum.map(&String.trim_trailing/1)
    |> trim_blank_edges()
    |> collapse_blank_run(1)
    |> reindent_lines(base_pad)
    |> Enum.join("\n")
  end

  @spec collapse_extra_newlines(String.t()) :: String.t()
  def collapse_extra_newlines(text) when is_binary(text) do
    Regex.replace(~r/\n{3,}/, text, "\n\n")
  end

  defp format_lines(lines) do
    {reversed, _depth, _switch_depth} =
      Enum.reduce(lines, {[], 0, nil}, fn line, {acc, depth, switch_depth} ->
        trimmed = String.trim_trailing(line)
        content = String.trim(trimmed)

        cond do
          content == "" ->
            {["" | acc], depth, switch_depth}

          preprocessor_line?(content) ->
            {[content | acc], depth, switch_depth}

          true ->
            depth_before = max(depth - leading_close_braces(content), 0)
            indent_level = effective_indent(depth_before, switch_depth, content)
            indent_cols = indent_level * @indent_unit
            formatted = String.duplicate(" ", indent_cols) <> content

            depth_after = depth_before + net_brace_delta(content)
            switch_after = update_switch_depth(content, depth_after, switch_depth)

            {[formatted | acc], max(depth_after, 0), switch_after}
        end
      end)

    Enum.reverse(reversed)
  end

  defp preprocessor_line?(line) do
    String.starts_with?(line, "#")
  end

  defp case_label?(line) do
    Regex.match?(~r/^case\s+.+:$/, line) or Regex.match?(~r/^default:\s*$/, line)
  end

  defp switch_opener?(line) do
    Regex.match?(~r/\bswitch\s*\(/, line) and String.contains?(line, "{")
  end

  defp effective_indent(depth, switch_depth, content) do
    cond do
      is_integer(switch_depth) and case_label?(content) ->
        switch_depth

      is_integer(switch_depth) and not String.starts_with?(content, "}") ->
        switch_depth + 1

      true ->
        depth
    end
  end

  defp update_switch_depth(content, depth_after, switch_depth) do
    cond do
      switch_opener?(content) ->
        depth_after

      is_integer(switch_depth) and depth_after < switch_depth ->
        nil

      true ->
        switch_depth
    end
  end

  defp leading_close_braces(line) do
    line
    |> String.graphemes()
    |> Enum.take_while(&(&1 == "}"))
    |> length()
  end

  defp net_brace_delta(line) do
    opens = count_char(line, ?{)
    closes = count_char(line, ?})
    leading = leading_close_braces(line)
    opens - (closes - leading)
  end

  defp count_char(line, ?{), do: String.count(line, "{")
  defp count_char(line, ?}), do: String.count(line, "}")

  defp trim_blank_edges(lines) do
    lines
    |> Enum.drop_while(&(String.trim(&1) == ""))
    |> Enum.reverse()
    |> Enum.drop_while(&(String.trim(&1) == ""))
    |> Enum.reverse()
  end

  defp collapse_blank_run(lines, max_run) when is_integer(max_run) and max_run >= 0 do
    Enum.reduce(lines, {[], 0}, fn line, {acc, blank_run} ->
      if String.trim(line) == "" do
        if blank_run < max_run do
          {["" | acc], blank_run + 1}
        else
          {acc, blank_run + 1}
        end
      else
        {[line | acc], 0}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp reindent_lines(lines, base_pad) do
    min_indent =
      lines
      |> Enum.filter(&(String.trim(&1) != ""))
      |> Enum.map(&leading_spaces/1)
      |> case do
        [] -> 0
        indents -> Enum.min(indents)
      end

    Enum.map(lines, fn
      "" ->
        ""

      line ->
        extra = max(leading_spaces(line) - min_indent, 0)
        base_pad <> String.duplicate(" ", extra) <> String.trim_leading(line)
    end)
  end

  defp leading_spaces(line) do
    line
    |> String.graphemes()
    |> Enum.take_while(&(&1 == " "))
    |> length()
  end
end
