defmodule Elmc.Backend.CCodegen.CSource do
  @moduledoc """
  Formatting and layout helpers for generated C source.

  Emitters should build C fragments with `indent/2` or `format_block/2`, then
  pass assembled translation units through `format/1` before writing files.
  """

  @indent_unit 2

  @spec format(String.t()) :: String.t()
  def format(source) when is_binary(source) do
    borrow_arg_callees = borrow_arg_callees(source)

    source
    |> compact_borrowed_record_field_call_temps(borrow_arg_callees)
    |> String.split("\n", trim: false)
    |> Enum.flat_map(&expand_compact_if_assignment_line/1)
    |> remove_adjacent_retain_release()
    |> Enum.map(&compact_unit_increment/1)
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

  defp expand_compact_if_assignment_line(line) do
    case Regex.run(~r/^(\s*)if \((.+)\) (.+);$/, line) do
      [_, indent, cond, body] ->
        if compact_if_assignment_body?(body) do
          ["#{indent}if (#{cond})", String.trim(body) <> ";"]
        else
          [line]
        end

      _ ->
        [line]
    end
  end

  defp remove_adjacent_retain_release(lines) do
    lines
    |> Enum.reduce([], fn line, acc ->
      case acc do
        [prev | rest] ->
          case adjacent_retain_release?(prev, line) do
            true -> rest
            false -> [line | acc]
          end

        [] ->
          [line]
      end
    end)
    |> Enum.reverse()
  end

  defp adjacent_retain_release?(retain_line, release_line) do
    with [_, tmp] <-
           Regex.run(
             ~r/^\s*ElmcValue \*(tmp_\d+) = elmc_retain\([A-Za-z_][A-Za-z0-9_]*\);\s*$/,
             retain_line
           ),
         true <- Regex.match?(~r/^\s*elmc_release\(#{Regex.escape(tmp)}\);\s*$/, release_line) do
      true
    else
      _ -> false
    end
  end

  defp borrow_arg_callees(source) do
    ~r/(?:static\s+)?ElmcValue \*(elmc_fn_[A-Za-z0-9_]+)\([^)]*\)\s*\{\s*\n\s*\/\* Ownership policy: [^*]*\bborrow_arg\b[^*]*\*\//
    |> Regex.scan(source)
    |> Enum.map(fn [_, callee] -> callee end)
    |> MapSet.new()
  end

  defp compact_borrowed_record_field_call_temps(source, callees) do
    Enum.reduce(callees, source, fn callee, acc ->
      acc
      |> compact_wrapper_borrowed_record_field_temp(callee)
      |> compact_direct_borrowed_record_field_temp(callee)
    end)
  end

  defp compact_wrapper_borrowed_record_field_temp(source, callee) do
    pattern =
      ~r/^(\s*)ElmcValue \*(tmp_\d+) = elmc_record_get_index\(([^;\n]+)\);\n\s*\n\s*ElmcValue \*(call_args_\d+)\[(\d+)\] = \{ ([^;\n{}]*?)\b\2\b([^;\n{}]*?) \};\n\s*ElmcValue \*(tmp_\d+) = #{Regex.escape(callee)}\(\4, \5\);\n\s*\n\s*elmc_release\(\2\);/m

    Regex.replace(pattern, source, fn _match,
                                      indent,
                                      _tmp,
                                      getter_args,
                                      call_args,
                                      arity,
                                      before,
                                      after_args,
                                      out ->
      borrowed = "ELMC_RECORD_GET_INDEX(#{getter_args})"

      """
      #{indent}ElmcValue *#{call_args}[#{arity}] = { #{before}#{borrowed}#{after_args} };
      #{indent}ElmcValue *#{out} = #{callee}(#{call_args}, #{arity});
      """
      |> String.trim_trailing()
    end)
  end

  defp compact_direct_borrowed_record_field_temp(source, callee) do
    pattern =
      ~r/^(\s*)ElmcValue \*(tmp_\d+) = elmc_record_get_index\(([^;\n]+)\);\n\s*\n\s*ElmcValue \*(tmp_\d+) = #{Regex.escape(callee)}\(([^;\n()]*?)\b\2\b([^;\n()]*?)\);\n\s*\n\s*elmc_release\(\2\);/m

    Regex.replace(pattern, source, fn _match,
                                      indent,
                                      _tmp,
                                      getter_args,
                                      out,
                                      before,
                                      after_args ->
      borrowed = "ELMC_RECORD_GET_INDEX(#{getter_args})"

      """
      #{indent}ElmcValue *#{out} = #{callee}(#{before}#{borrowed}#{after_args});
      """
      |> String.trim_trailing()
    end)
  end

  defp compact_unit_increment(line) do
    cond do
      match = Regex.run(~r/^(\s*)([A-Za-z_][A-Za-z0-9_]*(?:\[[^\]]+\])?)\s*\+=\s*1;\s*$/, line) ->
        [_, indent, target] = match
        "#{indent}#{target}++;"

      match = Regex.run(~r/^(\s*)([A-Za-z_][A-Za-z0-9_]*(?:\[[^\]]+\])?)\s*-=\s*1;\s*$/, line) ->
        [_, indent, target] = match
        "#{indent}#{target}--;"

      true ->
        line
    end
  end

  defp compact_if_assignment_body?(body) do
    Regex.match?(
      ~r/^[A-Za-z_][\w]*(\[[^\]]+\])?\s*(\+=|-=|\*=|\/=|%?=)/,
      String.trim(body)
    )
  end

  defp format_lines(lines) do
    {reversed, _depth, _switch_depth, _pending_if_body} =
      Enum.reduce(lines, {[], 0, nil, false}, fn line,
                                                 {acc, depth, switch_depth, pending_if_body} ->
        trimmed = String.trim_trailing(line)
        content = String.trim(trimmed)

        cond do
          content == "" ->
            {["" | acc], depth, switch_depth, pending_if_body}

          content == ";" ->
            {acc, depth, switch_depth, pending_if_body}

          preprocessor_line?(content) ->
            {[content | acc], depth, switch_depth, false}

          catch_end?(content) ->
            depth_before = max(depth - 1, 0)
            indent_cols = depth_before * @indent_unit
            formatted = String.duplicate(" ", indent_cols) <> content
            {[formatted | acc], depth_before, switch_depth, false}

          catch_begin?(content) ->
            indent_cols = depth * @indent_unit
            formatted = String.duplicate(" ", indent_cols) <> content
            {[formatted | acc], depth + 1, switch_depth, false}

          true ->
            depth_before = max(depth - leading_close_braces(content), 0)

            {indent_level, next_pending_if_body} =
              cond do
                pending_if_body ->
                  {depth_before + 1, false}

                braceless_if_opener?(content) ->
                  {depth_before, true}

                true ->
                  {depth_before, false}
              end

            indent_level = effective_indent(indent_level, switch_depth, content)
            indent_cols = indent_level * @indent_unit
            formatted = String.duplicate(" ", indent_cols) <> content

            depth_after = depth_before + net_brace_delta(content)
            switch_after = update_switch_depth(content, depth_after, switch_depth)

            {[formatted | acc], max(depth_after, 0), switch_after, next_pending_if_body}
        end
      end)

    Enum.reverse(reversed)
  end

  defp braceless_if_opener?(content) do
    Regex.match?(~r/^if\s*\(.+\)$/, content) and not String.contains?(content, "{")
  end

  defp preprocessor_line?(line) do
    String.starts_with?(line, "#")
  end

  defp catch_begin?(line), do: line == "CATCH_BEGIN"

  defp catch_end?(line) do
    line == "CATCH_END" or line == "CATCH_END;"
  end

  defp case_label?(line) do
    Regex.match?(~r/^case\s+.+:/, line) or Regex.match?(~r/^default:/, line)
  end

  defp switch_opener?(line) do
    Regex.match?(~r/\bswitch\s*\(/, line) and String.contains?(line, "{")
  end

  defp effective_indent(depth, switch_depth, content) do
    cond do
      is_integer(switch_depth) and case_label?(content) ->
        switch_depth

      is_integer(switch_depth) and not String.starts_with?(content, "}") and not case_label?(content) ->
        max(switch_depth + 1, depth)

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

  defp count_char(line, ?{), do: line |> String.codepoints() |> Enum.count(&(&1 == "{"))
  defp count_char(line, ?}), do: line |> String.codepoints() |> Enum.count(&(&1 == "}"))

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
