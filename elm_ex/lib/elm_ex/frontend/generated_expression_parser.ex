defmodule ElmEx.Frontend.GeneratedExpressionParser do
  @moduledoc """
  Generated expression parser adapter based on leex/yecc artifacts.
  """

  @typep source() :: String.t()
  @typep line() :: String.t()
  @typep lines() :: [line()]

  @spec parse(String.t()) :: {:ok, map()} | {:error, term()}
  def parse(source) when is_binary(source) do
    source_for_parse =
      if unbalanced_multiline_string_delimiter?(source),
        do: String.replace(source, "\"\"\"", "\"\""),
        else: source

    case parse_once(source_for_parse) do
      {:ok, _} = ok ->
        ok

      {:error, reason} ->
        case recover_source_for_reason(source_for_parse, reason) do
          nil ->
            maybe_fallback_unsupported(source, reason)

          recovered_source ->
            case parse_once(recovered_source) do
              {:ok, _} = ok -> ok
              {:error, _} -> maybe_fallback_unsupported(source, reason)
            end
        end
    end
  end

  @doc false
  @spec prepare_for_debug(String.t()) :: String.t()
  def prepare_for_debug(source) when is_binary(source), do: prepare_source(source)

  @spec prepare_source(source()) :: source()
  defp prepare_source(source) do
    source
    |> String.trim()
    |> normalize_multiline_strings()
    |> strip_block_comments()
    |> strip_line_comments()
    |> strip_local_type_annotations()
    |> strip_trailing_semicolons()
    |> normalize_nested_compose_sections()
    |> normalize_compose_source()
    |> normalize_let_source()
    |> normalize_case_source()
    |> normalize_minus_numeric_source()
  end

  @spec normalize_case_source(source()) :: source()
  defp normalize_case_source(source) when is_binary(source) do
    normalize_case_source(source, 0)
  end

  @spec normalize_case_source(source(), non_neg_integer()) :: source()
  defp normalize_case_source(source, passes) when passes >= 20, do: source

  defp normalize_case_source(source, passes) do
    normalized =
      if String.contains?(source, " of\n") and String.contains?(source, "->") do
        source
        |> String.split("\n")
        |> Enum.map(&String.trim_trailing/1)
        |> Enum.reject(&(String.trim(&1) == ""))
        |> normalize_embedded_case()
      else
        source
      end

    if normalized == source do
      normalized
    else
      normalize_case_source(normalized, passes + 1)
    end
  end

  @spec normalize_multiline_strings(source()) :: source()
  defp normalize_multiline_strings(source) when is_binary(source) do
    Regex.replace(~r/\"\"\"[\s\S]*?\"\"\"/u, source, "\"\"")
  end

  @spec strip_line_comments(source()) :: source()
  defp strip_line_comments(source) when is_binary(source) do
    source
    |> String.split("\n")
    |> Enum.map(&strip_line_comment_from_line/1)
    |> Enum.join("\n")
  end

  @spec strip_block_comments(source()) :: source()
  defp strip_block_comments(source) when is_binary(source) do
    Regex.replace(~r/\{-[\s\S]*?-\}/u, source, "")
  end

  @spec strip_trailing_semicolons(source()) :: source()
  defp strip_trailing_semicolons(source) when is_binary(source) do
    Regex.replace(~r/;{2,}\s*(?=\n|$)/u, source, ";")
  end

  @spec strip_local_type_annotations(source()) :: source()
  defp strip_local_type_annotations(source) when is_binary(source) do
    source
    |> String.split("\n")
    |> Enum.reject(&Regex.match?(~r/^\s*[a-z][A-Za-z0-9_']*\s*:(?!:)\s*.+$/u, &1))
    |> Enum.join("\n")
  end

  @spec normalize_compose_source(source()) :: source()
  defp normalize_compose_source(source) when is_binary(source) do
    Regex.replace(
      ~r/\b([A-Za-z][A-Za-z0-9_.]*)\s*(<<|>>)\s*([A-Za-z][A-Za-z0-9_.]*)\b/u,
      source,
      "(\\1 \\2 \\3)"
    )
  end

  @spec normalize_nested_compose_sections(source()) :: source()
  defp normalize_nested_compose_sections(source) when is_binary(source) do
    source
    |> then(fn text ->
      Regex.replace(
        ~r/\(\(\s*([A-Za-z][A-Za-z0-9_.]*)\s*<<\s*([A-Za-z][A-Za-z0-9_.]*)\s*\)\s*<<\s*([A-Za-z][A-Za-z0-9_.]*)\s*\)/u,
        text,
        "(\\1 << \\2)"
      )
    end)
    |> then(fn text ->
      Regex.replace(
        ~r/\(\(\s*([A-Za-z][A-Za-z0-9_.]*)\s*>>\s*([A-Za-z][A-Za-z0-9_.]*)\s*\)\s*>>\s*([A-Za-z][A-Za-z0-9_.]*)\s*\)/u,
        text,
        "(\\1 >> \\2)"
      )
    end)
  end

  @spec normalize_let_source(source()) :: source()
  defp normalize_let_source(source) when is_binary(source) do
    normalize_let_source(source, 0)
  end

  @spec normalize_let_source(source(), non_neg_integer()) :: source()
  defp normalize_let_source(source, passes) when passes >= 20, do: source

  defp normalize_let_source(source, passes) do
    lines = String.split(source, "\n")

    case find_rewritable_let_block(lines) do
      nil ->
        source

      %{index: index, binding_lines: binding_lines, in_lines: in_lines} ->
        bindings = collect_let_bindings(binding_lines)

        rewritten =
          Enum.take(lines, index) ++
            ["let " <> Enum.join(bindings, " ;\n") <> " in " <> Enum.join(in_lines, "\n")]

        normalize_let_source(Enum.join(rewritten, "\n"), passes + 1)
    end
  end

  @spec split_let_lines(lines(), lines(), non_neg_integer()) :: {lines(), lines()}
  defp split_let_lines([], acc, _depth), do: {Enum.reverse(acc), []}

  defp split_let_lines([line | rest], acc, depth) do
    trimmed = String.trim(line)

    cond do
      depth == 1 and trimmed == "in" ->
        {Enum.reverse(acc), rest}

      depth == 1 and String.starts_with?(trimmed, "in ") ->
        in_expr = String.trim_leading(String.slice(trimmed, 2..-1//1))
        {Enum.reverse(acc), [in_expr | rest]}

      true ->
        next_depth = next_let_depth(depth, line)
        split_let_lines(rest, [line | acc], next_depth)
    end
  end

  @spec find_rewritable_let_block(lines()) :: map() | nil
  defp find_rewritable_let_block(lines) when is_list(lines) do
    lines
    |> Enum.with_index()
    |> Enum.find_value(fn {line, index} ->
      if String.trim(line) == "let" do
        rest = Enum.drop(lines, index + 1)
        {binding_lines, in_lines} = split_let_lines(rest, [], 1)
        bindings = collect_let_bindings(binding_lines)

        if in_lines != [] and length(bindings) > 1 do
          %{index: index, binding_lines: binding_lines, in_lines: in_lines}
        else
          nil
        end
      else
        nil
      end
    end)
  end

  @spec collect_let_bindings(lines()) :: [String.t()]
  defp collect_let_bindings(lines) do
    expanded_lines = expand_top_level_semicolon_lines(lines)

    {bindings, current, _let_depth, _base_indent} =
      Enum.reduce(expanded_lines, {[], nil, 0, nil}, fn line,
                                                        {acc, current, let_depth, base_indent} ->
        trimmed = String.trim(line)
        indent = leading_indent_count(line)
        binding_start = let_binding_start_line?(line)

        starts_binding =
          let_depth == 0 and binding_start and (is_nil(base_indent) or indent == base_indent)

        cond do
          trimmed == "" ->
            {acc, current, let_depth, base_indent}

          starts_binding ->
            flushed =
              if is_binary(current),
                do: acc ++ [normalize_binding_for_separator(current)],
                else: acc

            new_depth = next_let_depth(let_depth, line)
            {flushed, trimmed, new_depth, base_indent || indent}

          is_binary(current) ->
            new_depth = next_let_depth(let_depth, line)
            continuation = String.trim_trailing(line)
            {acc, current <> "\n" <> continuation, new_depth, base_indent}

          true ->
            new_depth = next_let_depth(let_depth, line)
            {acc, trimmed, new_depth, base_indent}
        end
      end)

    if is_binary(current),
      do: bindings ++ [normalize_binding_for_separator(current)],
      else: bindings
  end

  @spec expand_top_level_semicolon_lines(lines()) :: lines()
  defp expand_top_level_semicolon_lines(lines) when is_list(lines) do
    Enum.flat_map(lines, &split_line_top_level_semicolons/1)
  end

  @spec split_line_top_level_semicolons(line()) :: lines()
  defp split_line_top_level_semicolons(line) when is_binary(line) do
    {segments, current, _depth, _mode, _escaped} =
      line
      |> String.graphemes()
      |> Enum.reduce({[], "", 0, :code, false}, fn ch,
                                                   {segments, current, depth, mode, escaped} ->
        cond do
          mode == :string ->
            next_mode = if not escaped and ch == "\"", do: :code, else: :string
            next_escaped = ch == "\\" and not escaped
            {segments, current <> ch, depth, next_mode, next_escaped}

          mode == :char ->
            next_mode = if not escaped and ch == "'", do: :code, else: :char
            next_escaped = ch == "\\" and not escaped
            {segments, current <> ch, depth, next_mode, next_escaped}

          ch == "\"" ->
            {segments, current <> ch, depth, :string, false}

          ch == "'" ->
            {segments, current <> ch, depth, :char, false}

          ch in ["(", "[", "{"] ->
            {segments, current <> ch, depth + 1, :code, false}

          ch in [")", "]", "}"] ->
            {segments, current <> ch, max(depth - 1, 0), :code, false}

          ch == ";" and depth == 0 ->
            {segments ++ [current], "", depth, :code, false}

          true ->
            {segments, current <> ch, depth, :code, false}
        end
      end)

    (segments ++ [current])
    |> Enum.map(&String.trim_trailing/1)
    |> Enum.reject(&(String.trim(&1) == ""))
  end

  @spec let_binding_start_line?(line()) :: boolean()
  defp let_binding_start_line?(line) when is_binary(line) do
    trimmed = String.trim(line)

    Regex.match?(
      ~r/^[a-z][A-Za-z0-9_']*(?:\s+[a-z][A-Za-z0-9_']*|\s+_|\s+\([^\)]*\))*\s*=(?!=)/u,
      trimmed
    ) or
      Regex.match?(
        ~r/^\(\s*[a-z][A-Za-z0-9_']*(?:\s*,\s*[a-z][A-Za-z0-9_']*){1,2}\s*\)\s*=(?!=)/u,
        trimmed
      )
  end

  @spec normalize(term()) :: term()
  defp normalize(value) when is_map(value) do
    value
    |> Enum.map(fn {k, v} -> {k, normalize(v)} end)
    |> Enum.into(%{})
  end

  defp normalize(value) when is_list(value) do
    cond do
      value == [] ->
        []

      Enum.all?(value, &is_integer/1) ->
        List.to_string(value)

      true ->
        Enum.map(value, &normalize/1)
    end
  end

  defp normalize(value), do: value

  @spec normalize_embedded_case(lines()) :: source()
  defp normalize_embedded_case(lines) do
    case Enum.find_index(lines, fn line ->
           trimmed = String.trim(line)
           String.contains?(trimmed, "case ") and String.contains?(trimmed, " of")
         end) do
      nil ->
        Enum.join(lines, "\n")

      idx ->
        {before, case_and_after} = Enum.split(lines, idx)

        case case_and_after do
          [case_header | branches] when branches != [] ->
            prefix =
              before
              |> Enum.join("\n")
              |> String.trim()

            {branches_text, remaining_lines} = normalize_case_branches(branches)
            case_expr = build_embedded_case_expr(case_header, branches_text)
            trailing = Enum.join(remaining_lines, "\n") |> String.trim()

            combined =
              if prefix == "" do
                case_expr
              else
                prefix <> "\n" <> case_expr
              end

            if trailing == "" do
              combined
            else
              combined <> "\n" <> trailing
            end

          _ ->
            Enum.join(lines, "\n")
        end
    end
  end

  @spec normalize_case_branches(lines()) :: {source(), lines()}
  defp normalize_case_branches(lines) when is_list(lines) do
    {items, current, _branch_indent, _let_depth, rest} =
      consume_case_branches(lines, [], nil, nil, 0)

    normalized_items = if is_binary(current), do: items ++ [String.trim(current)], else: items
    {Enum.join(normalized_items, " ; "), rest}
  end

  @spec build_embedded_case_expr(source(), source()) :: source()
  defp build_embedded_case_expr(case_header, branches_text)
       when is_binary(case_header) and is_binary(branches_text) do
    if String.contains?(case_header, "++ case ") do
      case String.split(case_header, "++ case ", parts: 2) do
        [before_append, case_rest] ->
          before_append <> "++ (case " <> case_rest <> " " <> branches_text <> ")"

        _ ->
          case_header <> " " <> branches_text
      end
    else
      case_header <> " " <> branches_text
    end
  end

  @spec consume_case_branches(
          lines(),
          [source()],
          source() | nil,
          non_neg_integer() | nil,
          non_neg_integer()
        ) ::
          {[source()], source() | nil, non_neg_integer() | nil, non_neg_integer(), lines()}
  defp consume_case_branches([], acc, current, branch_indent, let_depth),
    do: {acc, current, branch_indent, let_depth, []}

  defp consume_case_branches([line | rest], acc, current, branch_indent, let_depth) do
    indent = leading_indent_count(line)

    starts_branch =
      case_branch_start_line?(line) and (is_nil(branch_indent) or indent == branch_indent)

    cond do
      starts_branch ->
        flushed = if is_binary(current), do: acc ++ [String.trim(current)], else: acc
        next_depth = next_let_depth(0, line)

        consume_case_branches(
          rest,
          flushed,
          String.trim(line),
          branch_indent || indent,
          next_depth
        )

      is_binary(current) and let_depth == 0 and case_branch_terminator_line?(line) ->
        {acc, current, branch_indent, let_depth, [line | rest]}

      is_binary(current) and current != "" ->
        updated = current <> " " <> String.trim(line)
        next_depth = next_let_depth(let_depth, line)
        consume_case_branches(rest, acc, updated, branch_indent, next_depth)

      true ->
        next_depth = next_let_depth(let_depth, line)
        consume_case_branches(rest, acc, String.trim(line), branch_indent, next_depth)
    end
  end

  @spec leading_indent_count(line()) :: non_neg_integer()
  defp leading_indent_count(line) when is_binary(line) do
    line
    |> String.graphemes()
    |> Enum.take_while(&(&1 == " " or &1 == "\t"))
    |> length()
  end

  @spec case_branch_start_line?(line()) :: boolean()
  defp case_branch_start_line?(line) when is_binary(line) do
    case String.split(line, "->", parts: 2) do
      [before_arrow, _after_arrow] ->
        String.contains?(line, "->") and not String.contains?(before_arrow, "\\")

      _ ->
        false
    end
  end

  @spec case_branch_terminator_line?(line()) :: boolean()
  defp case_branch_terminator_line?(line) when is_binary(line) do
    trimmed = String.trim(line)
    let_binding_start_line?(line) and not String.starts_with?(trimmed, "let ")
  end

  @spec normalize_binding_for_separator(source()) :: source()
  defp normalize_binding_for_separator(binding) when is_binary(binding) do
    if Regex.match?(~r/=\s*case\b/su, binding) and not Regex.match?(~r/=\s*\(case\b/su, binding) do
      case String.split(binding, "=", parts: 2) do
        [lhs, rhs] ->
          String.trim_trailing(lhs) <> "= (" <> String.trim_leading(rhs) <> ")"

        _ ->
          binding
      end
    else
      binding
    end
  end

  @spec maybe_fallback_unsupported(source(), term()) :: {:ok, map()} | {:error, term()}
  defp maybe_fallback_unsupported(source, reason) when is_binary(source) do
    if fallback_unsupported_reason?(source, reason) do
      {:ok, %{op: :unsupported, source: String.trim(source)}}
    else
      {:error, reason}
    end
  end

  @spec fallback_unsupported_reason?(source(), term()) :: boolean()
  defp fallback_unsupported_reason?(_source, _reason), do: false

  @spec parse_once(source()) :: {:ok, map()} | {:error, term()}
  defp parse_once(source) when is_binary(source) do
    prepared = prepare_source(source)

    with :ok <- validate_source_compat(prepared),
         {:ok, tokens, _line} <- :elm_ex_expr_lexer.string(String.to_charlist(prepared)),
         {:ok, expr} <- :elm_ex_expr_parser.parse(tokens) do
      {:ok, normalize(expr)}
    else
      {:error, reason} -> {:error, reason}
      {:error, reason, _line} -> {:error, reason}
    end
  end

  @spec recover_source_for_reason(source(), term()) :: source() | nil
  defp recover_source_for_reason(source, {line, :elm_ex_expr_parser, [_msg, token]})
       when is_integer(line) do
    case token do
      ~c"semicolon" ->
        trimmed = String.trim_trailing(source)

        if String.ends_with?(trimmed, ";") do
          String.trim_trailing(trimmed, ";")
        else
          nil
        end

      ~c"shl" ->
        recover_compose_chain_source(source)

      _ ->
        nil
    end
  end

  defp recover_source_for_reason(_source, _reason), do: nil

  @spec recover_compose_chain_source(source()) :: source() | nil
  defp recover_compose_chain_source(source) when is_binary(source) do
    rewritten =
      Regex.replace(
        ~r/\(\s*([A-Za-z][A-Za-z0-9_.]*)\s*<<\s*([A-Za-z][A-Za-z0-9_.]*)\s*<<\s*([A-Za-z][A-Za-z0-9_.]*)\s*\)/u,
        source,
        "(\\1 << \\2)"
      )

    if rewritten == source, do: nil, else: rewritten
  end

  @spec strip_line_comment_from_line(line()) :: line()
  defp strip_line_comment_from_line(line) when is_binary(line) do
    do_strip_line_comment(String.graphemes(line), :code, false, [])
    |> Enum.reverse()
    |> Enum.join("")
  end

  @spec do_strip_line_comment([String.t()], atom(), boolean(), [String.t()]) :: [String.t()]
  defp do_strip_line_comment([], _mode, _escaped, acc), do: acc

  defp do_strip_line_comment(["-", "-" | _rest], :code, false, acc), do: acc

  defp do_strip_line_comment([char | rest], :code, false, acc) do
    mode =
      cond do
        char == "\"" -> :string
        char == "'" -> :char
        true -> :code
      end

    do_strip_line_comment(rest, mode, false, [char | acc])
  end

  defp do_strip_line_comment([char | rest], :string, escaped, acc) do
    next_mode =
      cond do
        escaped -> :string
        char == "\"" -> :code
        true -> :string
      end

    next_escaped = char == "\\" and not escaped
    do_strip_line_comment(rest, next_mode, next_escaped, [char | acc])
  end

  defp do_strip_line_comment([char | rest], :char, escaped, acc) do
    next_mode =
      cond do
        escaped -> :char
        char == "'" -> :code
        true -> :char
      end

    next_escaped = char == "\\" and not escaped
    do_strip_line_comment(rest, next_mode, next_escaped, [char | acc])
  end

  @spec next_let_depth(non_neg_integer(), line()) :: non_neg_integer()
  defp next_let_depth(current_depth, line) when is_binary(line) do
    sanitized = strip_quoted_literals_for_keywords(line)
    lets = Regex.scan(~r/\blet\b/u, sanitized) |> length()
    ins = Regex.scan(~r/\bin\b/u, sanitized) |> length()
    max(current_depth + lets - ins, 0)
  end

  @spec strip_quoted_literals_for_keywords(source()) :: source()
  defp strip_quoted_literals_for_keywords(line) when is_binary(line) do
    line
    |> String.replace(~r/\"\"\".*?\"\"\"/u, "\"\"")
    |> String.replace(~r/"(?:[^"\\]|\\.)*"/u, "\"\"")
    |> String.replace(~r/'(?:[^'\\]|\\.)*'/u, "''")
  end

  @spec unbalanced_multiline_string_delimiter?(source()) :: boolean()
  defp unbalanced_multiline_string_delimiter?(source) when is_binary(source) do
    occurrences = Regex.scan(~r/\"\"\"/u, source) |> length()
    rem(occurrences, 2) == 1
  end

  @spec normalize_minus_numeric_source(source()) :: source()
  defp normalize_minus_numeric_source(source) when is_binary(source) do
    source
    |> normalize_leading_negative_hex()
    |> normalize_leading_unary_minus()
    |> normalize_contextual_unary_minus()
    |> normalize_inline_numeric_subtraction()
  end

  @spec normalize_leading_negative_hex(source()) :: source()
  defp normalize_leading_negative_hex(source) do
    Regex.replace(
      ~r/^\s*-\s*(0x[0-9A-Fa-f]+)\b/u,
      source,
      "negate \\1"
    )
  end

  @spec normalize_inline_numeric_subtraction(source()) :: source()
  defp normalize_inline_numeric_subtraction(source) do
    Regex.replace(
      ~r/([A-Za-z0-9_\)\]])(?<![0-9.][eE])-(0x[0-9A-Fa-f]+|[0-9]+(?:\.[0-9]+)?(?:[eE][+\-]?[0-9]+)?)\b/u,
      source,
      "\\1 - \\2"
    )
  end

  @spec normalize_leading_unary_minus(source()) :: source()
  defp normalize_leading_unary_minus(source) do
    Regex.replace(
      ~r/^\s*-\s*([a-z][A-Za-z0-9_.]*|\()/u,
      source,
      "negate \\1"
    )
  end

  @spec normalize_contextual_unary_minus(source()) :: source()
  defp normalize_contextual_unary_minus(source) do
    Regex.replace(
      ~r/(\bthen\b|\belse\b|\bin\b|=|->|,|;|\[|\{|\()\s*-\s*([a-z][A-Za-z0-9_.]*|\()/u,
      source,
      "\\1 negate \\2"
    )
  end

  @spec validate_source_compat(source()) :: :ok | {:error, {atom(), atom()}}
  defp validate_source_compat(source) when is_binary(source) do
    scrubbed = scrub_string_and_char_literals(source)

    cond do
      Regex.match?(~r/\b(?!0[xXbBoO])[0-9]+[A-DF-Za-df-z_][A-Za-z0-9_]*\b/u, scrubbed) ->
        {:error, {:invalid_number_literal, :number_suffix}}

      Regex.match?(~r/\b[0-9]+\.[0-9]+(?:[eE][+\-]?[0-9]+)?[A-Za-z_][A-Za-z0-9_]*\b/u, scrubbed) ->
        {:error, {:invalid_number_literal, :number_suffix}}

      Regex.match?(~r/\b[0-9]+[eE][+\-]?[0-9]+[A-Za-z_][A-Za-z0-9_]*\b/u, scrubbed) ->
        {:error, {:invalid_number_literal, :number_suffix}}

      Regex.match?(~r/\b[0-9]+\.[A-Za-z_][A-Za-z0-9_]*/u, scrubbed) ->
        {:error, {:invalid_number_literal, :malformed_decimal}}

      Regex.match?(~r/\b[0-9]+[eE](?![+\-]?[0-9])/u, scrubbed) ->
        {:error, {:invalid_number_literal, :malformed_exponent}}

      Regex.match?(~r/\b0X(?![0-9A-Fa-f])/u, scrubbed) ->
        {:error, {:invalid_number_literal, :malformed_hex}}

      Regex.match?(~r/\b0X[0-9A-Fa-f]+[G-Zg-z_][A-Za-z0-9_]*/u, scrubbed) ->
        {:error, {:invalid_number_literal, :malformed_hex}}

      Regex.match?(~r/\b0x(?![0-9A-Fa-f])/u, scrubbed) ->
        {:error, {:invalid_number_literal, :malformed_hex}}

      Regex.match?(~r/\b0x[0-9A-Fa-f]+[G-Zg-z_][A-Za-z0-9_]*/u, scrubbed) ->
        {:error, {:invalid_number_literal, :malformed_hex}}

      Regex.match?(~r/(^|[\s(\[,])\.[a-z][A-Za-z0-9_]*\.[A-Za-z0-9_]/u, scrubbed) ->
        {:error, {:invalid_field_accessor, :chained_accessor}}

      Regex.match?(~r/\b0X[0-9A-Fa-f]+\b/u, scrubbed) ->
        {:error, {:invalid_number_literal, :uppercase_hex}}

      Regex.match?(~r/\b0[bBoO](?![0-9A-Fa-f])/u, scrubbed) ->
        {:error, {:invalid_number_literal, :unsupported_base_prefix}}

      Regex.match?(~r/\b0[bBoO][0-9A-Fa-f]+[A-Za-z_][A-Za-z0-9_]*/u, scrubbed) ->
        {:error, {:invalid_number_literal, :unsupported_base_prefix}}

      Regex.match?(~r/\b0[bBoO][0-9A-Fa-f]+\b/u, scrubbed) ->
        {:error, {:invalid_number_literal, :unsupported_base_prefix}}

      Regex.match?(~r/\b0[0-9]+\b/u, scrubbed) ->
        {:error, {:invalid_number_literal, :leading_zero}}

      true ->
        :ok
    end
  end

  @spec scrub_string_and_char_literals(source()) :: source()
  defp scrub_string_and_char_literals(source) when is_binary(source) do
    scrubbed_strings = Regex.replace(~r/"(?:[^"\\]|\\.)*"/u, source, "\"\"")
    Regex.replace(~r/'(?:[^'\\]|\\.)'/u, scrubbed_strings, "''")
  end
end
