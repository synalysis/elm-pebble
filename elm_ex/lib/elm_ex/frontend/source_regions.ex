defmodule ElmEx.Frontend.SourceRegions do
  @moduledoc """
  Extract preamble, module header, and import regions from Elm source for preserve-mode formatting.
  """

  @type t :: %{
          required(:preamble) => String.t(),
          required(:header) => String.t(),
          required(:pre_import) => String.t(),
          required(:imports) => String.t(),
          required(:pre_body) => String.t(),
          required(:body_line_start) => pos_integer()
        }

  @doc """
  Split module source into preamble/header/imports/body start line.
  """
  @spec extract(String.t()) :: t()
  def extract(source) when is_binary(source) do
    lines = String.split(source, "\n", trim: false)

    {preamble_lines, idx} = take_preamble(lines, 0)
    {header_lines, idx} = take_header(lines, idx)
    {pre_import_lines, idx, depth} = take_gap_until_depth(lines, idx, 0)
    {import_lines, idx, depth} = take_imports_depth(lines, idx, depth)
    {pre_body_lines, idx, _depth} = take_pre_body_gap_depth(lines, idx, depth)

    %{
      preamble: join_lines(preamble_lines),
      header: join_lines(header_lines),
      pre_import: join_lines(pre_import_lines),
      imports: join_lines(import_lines),
      pre_body: join_lines(pre_body_lines),
      body_line_start: idx + 1
    }
  end

  @spec take_preamble([String.t()], non_neg_integer()) :: {[String.t()], non_neg_integer()}
  defp take_preamble(lines, idx) do
    case Enum.at(lines, idx) do
      nil ->
        {[], idx}

      line ->
        if module_start_line?(line) do
          {[], idx}
        else
          {rest, next} = take_preamble(lines, idx + 1)
          {[line | rest], next}
        end
    end
  end

  @spec take_header([String.t()], non_neg_integer()) :: {[String.t()], non_neg_integer()}
  defp take_header(lines, idx) do
    case Enum.at(lines, idx) do
      nil ->
        {[], idx}

      line ->
        if module_start_line?(line) do
          do_take_header(lines, idx, [], false, 0)
        else
          {[], idx}
        end
    end
  end

  @spec do_take_header([String.t()], non_neg_integer(), [String.t()], boolean(), integer()) ::
          {[String.t()], non_neg_integer()}
  defp do_take_header(lines, idx, acc, saw_exposing, depth) do
    case Enum.at(lines, idx) do
      nil ->
        {Enum.reverse(acc), idx}

      line ->
        trimmed = String.trim_leading(line)
        acc = [line | acc]
        has_exposing = saw_exposing or exposing_keyword?(trimmed)
        new_depth = if has_exposing, do: depth + paren_delta(line), else: 0

        complete? =
          cond do
            has_exposing and new_depth == 0 and String.contains?(line, ")") ->
              true

            not has_exposing and module_header_complete?(trimmed) ->
              true

            true ->
              false
          end

        if complete? do
          {Enum.reverse(acc), idx + 1}
        else
          do_take_header(lines, idx + 1, acc, has_exposing, max(new_depth, 0))
        end
    end
  end

  @spec take_gap_until_depth([String.t()], non_neg_integer(), non_neg_integer()) ::
          {[String.t()], non_neg_integer(), non_neg_integer()}
  defp take_gap_until_depth(lines, idx, depth) do
    case Enum.at(lines, idx) do
      nil ->
        {[], idx, depth}

      line ->
        if depth == 0 and (import_start_line?(line) or top_level_declaration_line?(line)) do
          {[], idx, depth}
        else
          new_depth = advance_comment_depth(line, depth)
          {rest, next, final_depth} = take_gap_until_depth(lines, idx + 1, new_depth)
          {[line | rest], next, final_depth}
        end
    end
  end

  @spec take_imports_depth([String.t()], non_neg_integer(), non_neg_integer()) ::
          {[String.t()], non_neg_integer(), non_neg_integer()}
  defp take_imports_depth(lines, idx, depth) do
    line = Enum.at(lines, idx)

    if depth == 0 and import_start_line?(line) do
      do_take_imports_depth(lines, idx, [], 0, false, depth)
    else
      {[], idx, depth}
    end
  end

  @spec do_take_imports_depth([String.t()], non_neg_integer(), [String.t()], integer(), boolean(), non_neg_integer()) ::
          {[String.t()], non_neg_integer(), non_neg_integer()}
  defp do_take_imports_depth(lines, idx, acc, paren_depth, in_stanza, comment_depth) do
    case Enum.at(lines, idx) do
      nil ->
        {Enum.reverse(acc), idx, comment_depth}

      line ->
        trimmed = String.trim_leading(line)
        comment_depth = advance_comment_depth(line, comment_depth)

        cond do
          comment_depth > 0 ->
            do_take_imports_depth(lines, idx + 1, [line | acc], paren_depth, in_stanza, comment_depth)

          trimmed == "" ->
            case Enum.at(lines, idx + 1) do
              nil ->
                {Enum.reverse(acc), idx, comment_depth}

              next ->
                if import_start_line?(next) or import_continuation_line?(next, paren_depth) do
                  do_take_imports_depth(lines, idx + 1, [line | acc], paren_depth, in_stanza, comment_depth)
                else
                  {Enum.reverse(acc), idx, comment_depth}
                end
            end

          import_start_line?(line) ->
            do_take_imports_depth(lines, idx + 1, [line | acc], 0, true, comment_depth)

          in_stanza or paren_depth > 0 or import_continuation_line?(line, paren_depth) ->
            new_depth = max(paren_depth + paren_delta(line), 0)
            do_take_imports_depth(lines, idx + 1, [line | acc], new_depth, true, comment_depth)

          true ->
            {Enum.reverse(acc), idx, comment_depth}
        end
    end
  end

  @spec take_pre_body_gap_depth([String.t()], non_neg_integer(), non_neg_integer()) ::
          {[String.t()], non_neg_integer(), non_neg_integer()}
  defp take_pre_body_gap_depth(lines, idx, depth) do
    case Enum.at(lines, idx) do
      nil ->
        {[], idx, depth}

      line ->
        if depth == 0 and pre_body_gap_line?(line) do
          {block_lines, next, depth} = take_pre_body_gap_block_depth(lines, idx, line, depth)
          {rest, after_block, final_depth} = take_pre_body_gap_depth(lines, next, depth)
          {block_lines ++ rest, after_block, final_depth}
        else
          {[], idx, advance_comment_depth(line, depth)}
        end
    end
  end

  @spec take_pre_body_gap_block_depth([String.t()], non_neg_integer(), String.t(), non_neg_integer()) ::
          {[String.t()], non_neg_integer(), non_neg_integer()}
  defp take_pre_body_gap_block_depth(lines, idx, line, depth) do
    if doc_comment_start_line?(line) do
      take_doc_comment_block_depth(lines, idx, [], depth)
    else
      depth = advance_comment_depth(line, depth)
      {[line], idx + 1, depth}
    end
  end

  @spec take_doc_comment_block_depth([String.t()], non_neg_integer(), [String.t()], non_neg_integer()) ::
          {[String.t()], non_neg_integer(), non_neg_integer()}
  defp take_doc_comment_block_depth(lines, idx, acc, depth) do
    case Enum.at(lines, idx) do
      nil ->
        {Enum.reverse(acc), idx, depth}

      line ->
        depth = advance_comment_depth(line, depth)
        acc = [line | acc]

        if doc_comment_end_line?(line) and depth == 0 do
          {Enum.reverse(acc), idx + 1, depth}
        else
          take_doc_comment_block_depth(lines, idx + 1, acc, depth)
        end
    end
  end

  @spec advance_comment_depth(String.t(), non_neg_integer()) :: non_neg_integer()
  defp advance_comment_depth(line, depth) when is_binary(line) do
    do_advance_comment_depth(line, depth)
  end

  defp do_advance_comment_depth(<<>>, depth), do: depth

  defp do_advance_comment_depth(<<"{-", rest::binary>>, depth) do
    do_advance_comment_depth(rest, depth + 1)
  end

  defp do_advance_comment_depth(<<"-}", rest::binary>>, depth) when depth > 0 do
    do_advance_comment_depth(rest, depth - 1)
  end

  defp do_advance_comment_depth(<<_char::utf8, rest::binary>>, depth) do
    do_advance_comment_depth(rest, depth)
  end

  @spec pre_body_gap_line?(String.t()) :: boolean()
  defp pre_body_gap_line?(line) when is_binary(line) do
    trimmed = String.trim_leading(line)

    trimmed == "" or section_comment_line?(trimmed) or doc_comment_start_line?(line)
  end

  defp pre_body_gap_line?(_), do: false

  @spec section_comment_line?(String.t()) :: boolean()
  defp section_comment_line?(trimmed) do
    String.starts_with?(trimmed, "--") or
      (String.starts_with?(trimmed, "{-") and not String.starts_with?(trimmed, "{-|"))
  end

  @spec doc_comment_start_line?(String.t()) :: boolean()
  defp doc_comment_start_line?(line) when is_binary(line) do
    String.trim_leading(line) |> String.starts_with?("{-|")
  end

  defp doc_comment_start_line?(_), do: false

  defp doc_comment_end_line?(line) when is_binary(line) do
    String.trim_leading(line) |> String.ends_with?("-}")
  end

  @spec top_level_declaration_line?(String.t()) :: boolean()
  defp top_level_declaration_line?(line) when is_binary(line) do
    trimmed = String.trim_leading(line)

    trimmed != "" and
      (keyword_declaration_line?(trimmed) or named_declaration_line?(trimmed) or
         value_binding_header_line?(trimmed))
  end

  defp top_level_declaration_line?(_), do: false

  @spec keyword_declaration_line?(String.t()) :: boolean()
  defp keyword_declaration_line?(trimmed) do
    String.starts_with?(trimmed, "type ") or String.starts_with?(trimmed, "port ") or
      String.starts_with?(trimmed, "infix ")
  end

  @spec named_declaration_line?(String.t()) :: boolean()
  defp named_declaration_line?(trimmed), do: declaration_name_line?(trimmed)

  @spec value_binding_header_line?(String.t()) :: boolean()
  defp value_binding_header_line?(trimmed) do
    Regex.match?(~r/\s=\s*$/u, trimmed)
  end

  @spec declaration_name_line?(String.t()) :: boolean()
  defp declaration_name_line?(trimmed) do
    case Regex.run(~r/^([A-Za-z_][\w']*)\s*(:|=)/u, trimmed) do
      [_, _, _] -> true
      _ -> false
    end
  end

  @spec module_start_line?(String.t()) :: boolean()
  defp module_start_line?(line) when is_binary(line) do
    trimmed = String.trim_leading(line)
    module_declaration_start?(trimmed)
  end

  defp module_start_line?(_), do: false

  @spec module_declaration_start?(String.t()) :: boolean()
  defp module_declaration_start?(trimmed) do
    Regex.match?(~r/^(?:(?:port|effect)\s+)*module\b/u, trimmed) or
      Regex.match?(~r/^(?:port|effect)\b.*\bmodule\b/u, trimmed)
  end

  @spec module_header_complete?(String.t()) :: boolean()
  defp module_header_complete?(trimmed) do
    module_declaration_start?(trimmed) and
      Regex.match?(~r/\bmodule\s+\S+/u, trimmed) and
      not String.ends_with?(trimmed, "module") and
      not exposing_keyword?(trimmed)
  end

  @spec exposing_keyword?(String.t()) :: boolean()
  defp exposing_keyword?(trimmed) do
    Regex.match?(~r/\bexposing\b/u, trimmed)
  end

  @spec import_start_line?(String.t() | nil) :: boolean()
  defp import_start_line?(line) when is_binary(line) do
    String.trim_leading(line) |> String.starts_with?("import")
  end

  defp import_start_line?(_), do: false

  @spec import_continuation_line?(String.t(), integer()) :: boolean()
  defp import_continuation_line?(line, paren_depth) when is_binary(line) do
    leading_indent(line) > 0 or paren_depth > 0 or
      String.trim_leading(line) in [")", "exposing", "as"]
  end

  @spec paren_delta(String.t()) :: integer()
  defp paren_delta(line) do
    opens = line |> String.graphemes() |> Enum.count(&(&1 == "("))
    closes = line |> String.graphemes() |> Enum.count(&(&1 == ")"))
    opens - closes
  end

  @spec leading_indent(String.t()) :: non_neg_integer()
  defp leading_indent(line) do
    String.length(line) - String.length(String.trim_leading(line))
  end

  @spec join_lines([String.t()]) :: String.t()
  defp join_lines([]), do: ""

  defp join_lines(lines) do
    lines
    |> Enum.map_join("", &(&1 <> "\n"))
  end

  @doc """
  Stitch preserved regions with freshly formatted declarations.
  """
  @spec stitch(t(), String.t()) :: String.t()
  def stitch(
        %{
          preamble: preamble,
          header: header,
          pre_import: pre_import,
          imports: imports,
          pre_body: pre_body
        },
        declarations
      )
      when is_binary(declarations) do
    preamble
    |> combine_region(header)
    |> combine_region(pre_import)
    |> combine_region(imports)
    |> combine_region(pre_body)
    |> combine_region(declarations)
  end

  @spec combine_region(String.t(), String.t()) :: String.t()
  defp combine_region(left, ""), do: left
  defp combine_region("", right), do: right

  defp combine_region(left, right) do
    if String.ends_with?(left, "\n"), do: left <> right, else: left <> "\n" <> right
  end
end
