defmodule ElmEx.Frontend.GeneratedExpressionParser do
  @moduledoc """
  Generated expression parser adapter based on leex/yecc artifacts.
  """

  alias ElmEx.Frontend.AstContract.Types, as: AstTypes
  alias ElmEx.Frontend.LetLayout
  alias ElmEx.Types

  @typep source() :: String.t()
  @typep line() :: String.t()
  @typep lines() :: [line()]
  @typep expr() :: AstTypes.expr()
  @typep normalized_value() :: AstTypes.expr() | list() | String.t() | number() | boolean() | nil | atom()

  @typep let_rewrite_block :: %{
          index: non_neg_integer(),
          bindings: [String.t()],
          in_lines: lines()
        }

  @spec parse(String.t()) :: {:ok, expr()} | {:error, Types.parse_error_reason()}
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
    |> collapse_standalone_record_update_bars()
    |> collapse_binding_rhs_starts()
    |> strip_local_type_annotations()
    |> strip_trailing_semicolons()
    |> normalize_nested_compose_sections()
    |> normalize_compose_source()
    |> normalize_let_source()
    |> normalize_case_source()
    |> fix_record_update_bar_paren_glitch()
    |> fix_inline_let_multiple_bindings()
    |> normalize_inline_case_branch_separators()
    |> String.replace(~r/\bof\s*;;\s*/u, "of ")
    |> normalize_minus_numeric_source()
    |> normalize_trailing_commas()
    |> close_unbalanced_brackets_before_final_pipe()
    |> close_unbalanced_parens()
    |> split_inline_let_in_lines()
  end

  @spec collapse_binding_rhs_starts(source()) :: source()
  defp collapse_binding_rhs_starts(source) when is_binary(source) do
    # Many Elm bindings are written as:
    #   name =
    #     case ... of
    # Normalize to:
    #   name = case ... of
    source
    |> then(&Regex.replace(~r/=\s*\n\s*(case\b|if\b|\\)/u, &1, "= \\1"))
    |> collapse_case_branch_rhs_starts()
  end

  @spec collapse_case_branch_rhs_starts(source()) :: source()
  defp collapse_case_branch_rhs_starts(source) when is_binary(source) do
    # Case branches commonly continue with a nested `case` on the next line:
    #   Just x ->
    #     case ... of
    # The layout lexer treats the newline as a branch boundary; keep the nested
    # case on the same line so yecc can parse the branch body.
    Regex.replace(~r/->\s*\n\s*(case\b)/u, source, "-> \\1")
  end

  @spec close_unbalanced_parens(source()) :: source()
  defp close_unbalanced_parens(source) when is_binary(source) do
    # Layout normalization sometimes wraps large branches in parentheses; when a rewrite
    # drops a closing paren near the end, yecc reports an EOF parse error. Recover by
    # appending up to a small number of ')' to restore balance.
    diff = paren_balance_outside_string_literals(source)

    if diff > 0 and diff <= 3 do
      source <> String.duplicate(")", diff)
    else
      source
    end
  end

  @spec paren_balance_outside_string_literals(source()) :: integer()
  defp paren_balance_outside_string_literals(source) when is_binary(source) do
    source
    |> String.to_charlist()
    |> count_paren_balance(:code, 0)
  end

  defp count_paren_balance([], _state, acc), do: acc

  defp count_paren_balance([?( | rest], :code, acc),
    do: count_paren_balance(rest, :code, acc + 1)

  defp count_paren_balance([?) | rest], :code, acc),
    do: count_paren_balance(rest, :code, acc - 1)

  defp count_paren_balance([?" | rest], :code, acc),
    do: count_paren_balance(rest, :string, acc)

  defp count_paren_balance([?" | rest], :string, acc),
    do: count_paren_balance(rest, :code, acc)

  defp count_paren_balance([?' | rest], :code, acc),
    do: count_paren_balance(rest, :char, acc)

  defp count_paren_balance([?' | rest], :char, acc),
    do: count_paren_balance(rest, :code, acc)

  defp count_paren_balance([?\\, _ | rest], :string, acc),
    do: count_paren_balance(rest, :string, acc)

  defp count_paren_balance([?\\, _ | rest], :char, acc),
    do: count_paren_balance(rest, :char, acc)

  defp count_paren_balance([_ | rest], state, acc),
    do: count_paren_balance(rest, state, acc)

  @spec fix_record_update_bar_paren_glitch(source()) :: source()
  defp fix_record_update_bar_paren_glitch(source) when is_binary(source) do
    # After aggressive case/layout normalization, a record-update bar line that used
    # to be `| -- comment` can end up as `|) field = ...` (the `)` belongs to an
    # outer tuple paren, not the record update). This rewrite is conservative:
    # only fix the exact `|)` sequence when it is immediately followed by a field.
    Regex.replace(~r/\|\)\s*([a-z][A-Za-z0-9_']*\s*=)/u, source, "| \\1")
  end

  @spec fix_inline_let_multiple_bindings(source()) :: source()
  defp fix_inline_let_multiple_bindings(source) when is_binary(source) do
    # The token parser requires `;` between let bindings. After layout/case normalization
    # we sometimes end up with multiple bindings on one line:
    #   let starter = (case ...) introduction = ...
    # Recover by inserting `;` before the second binding.
    source
    |> String.split("\n")
    |> Enum.map(fn line ->
      trimmed = String.trim(line)

      if String.contains?(trimmed, "let ") and String.contains?(trimmed, " in") do
        Regex.replace(~r/\)\s+([a-z][A-Za-z0-9_']*)\s*=/u, line, ") ; \\1 =")
      else
        line
      end
    end)
    |> Enum.join("\n")
  end

  @spec collapse_standalone_record_update_bars(source()) :: source()
  defp collapse_standalone_record_update_bars(source) when is_binary(source) do
    source
    |> String.split("\n")
    |> do_collapse_standalone_record_update_bars([])
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp do_collapse_standalone_record_update_bars([], acc), do: acc

  defp do_collapse_standalone_record_update_bars([line | rest], []) do
    do_collapse_standalone_record_update_bars(rest, [line])
  end

  defp do_collapse_standalone_record_update_bars([line | rest], [prev | acc_tail] = acc) do
    if String.trim(line) == "|" do
      do_collapse_standalone_record_update_bars(rest, [prev <> " |" | acc_tail])
    else
      do_collapse_standalone_record_update_bars(rest, [line | acc])
    end
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

  @spec expand_case_of_to_newline(source()) :: source()
  defp expand_case_of_to_newline(source) when is_binary(source) do
    String.replace(source, ~r/\sof\s+(?=[(\[]|_|'|\"|[A-Z]|[a-z])/u, " of\n")
  end

  @spec normalize_multiline_strings(source()) :: source()
  defp normalize_multiline_strings(source) when is_binary(source) do
    Regex.replace(~r/\"\"\"([\s\S]*?)\"\"\"/u, source, fn _full, inner ->
      "\"#{escape_string_literal(inner)}\""
    end)
  end

  @spec escape_string_literal(String.t()) :: String.t()
  defp escape_string_literal(text) when is_binary(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\r\n", "\\n")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
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
    |> drop_local_type_annotation_lines([], :keep)
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp drop_local_type_annotation_lines([], acc, _mode), do: acc

  defp drop_local_type_annotation_lines([line | rest], acc, :dropping) do
    cond do
      String.trim(line) == "" ->
        drop_local_type_annotation_lines(rest, [line | acc], :keep)

      # Stop dropping once we hit a binding line (very permissive: any '=' in the line).
      String.contains?(line, "=") ->
        drop_local_type_annotation_lines(rest, [line | acc], :keep)

      true ->
        drop_local_type_annotation_lines(rest, acc, :dropping)
    end
  end

  defp drop_local_type_annotation_lines([line | rest], acc, :keep) do
    cond do
      # Single-line annotation: `name : Type`
      Regex.match?(~r/^\s*[a-z][A-Za-z0-9_']*\s*:(?!:)\s*.+$/u, line) ->
        drop_local_type_annotation_lines(rest, acc, :keep)

      # Multi-line annotation start: `name :` (no rhs on same line)
      Regex.match?(~r/^\s*[a-z][A-Za-z0-9_']*\s*:(?!:)\s*$/u, line) ->
        drop_local_type_annotation_lines(rest, acc, :dropping)

      true ->
        drop_local_type_annotation_lines(rest, [line | acc], :keep)
    end
  end

  @spec normalize_compose_source(source()) :: source()
  defp normalize_compose_source(source) when is_binary(source) do
    Regex.replace(
      # Do not parenthesize when the RHS continues with a qualified segment (for example
      # `GotWeather << Result.map` must not become `(GotWeather << Result).map`).
      ~r/(?<![A-Za-z0-9_.])([A-Za-z_][A-Za-z0-9_]*)\s*(<<|>>)\s*([A-Za-z_][A-Za-z0-9_]*)\b(?![A-Za-z0-9_.])/u,
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

      %{index: index, bindings: bindings, in_lines: in_lines} ->
        rewritten =
          Enum.take(lines, index) ++
            [
              "let " <> Enum.join(bindings, " ;\n"),
              "in",
              Enum.join(in_lines, "\n")
            ]

        normalize_let_source(Enum.join(rewritten, "\n"), passes + 1)
    end
  end

  @inline_let_in_line ~r/\blet\s+.+\s+in(\s+|$)/u

  @spec close_unbalanced_brackets_before_final_pipe(source()) :: source()
  defp close_unbalanced_brackets_before_final_pipe(source) when is_binary(source) do
    if list_bracket_depth(source) > 0 do
      lines =
        source
        |> String.split("\n")
        |> Enum.reject(&(String.trim(&1) == ""))

      case List.last(lines) do
        line when is_binary(line) ->
          trimmed = String.trim(line)

          if String.starts_with?(trimmed, "|>") do
            indent = String.duplicate(" ", leading_indent_count(line))
            prefix = Enum.drop(lines, -1)
            Enum.join(prefix ++ [indent <> "]", line], "\n")
          else
            source
          end

        _ ->
          source
      end
    else
      source
    end
  end

  @spec list_bracket_depth(source()) :: integer()
  defp list_bracket_depth(source) when is_binary(source) do
    source
    |> String.to_charlist()
    |> count_bracket_balance(:code, 0)
  end

  defp count_bracket_balance([], _state, acc), do: acc

  defp count_bracket_balance([?[ | rest], :code, acc),
    do: count_bracket_balance(rest, :code, acc + 1)

  defp count_bracket_balance([?] | rest], :code, acc),
    do: count_bracket_balance(rest, :code, acc - 1)

  defp count_bracket_balance([?" | rest], :code, acc),
    do: count_bracket_balance(rest, :string, acc)

  defp count_bracket_balance([?" | rest], :string, acc),
    do: count_bracket_balance(rest, :code, acc)

  defp count_bracket_balance([?' | rest], :code, acc),
    do: count_bracket_balance(rest, :char, acc)

  defp count_bracket_balance([?' | rest], :char, acc),
    do: count_bracket_balance(rest, :code, acc)

  defp count_bracket_balance([?\\, _ | rest], :string, acc),
    do: count_bracket_balance(rest, :string, acc)

  defp count_bracket_balance([?\\, _ | rest], :char, acc),
    do: count_bracket_balance(rest, :char, acc)

  defp count_bracket_balance([_ | rest], state, acc),
    do: count_bracket_balance(rest, state, acc)

  @spec split_inline_let_in_lines(source()) :: source()
  defp split_inline_let_in_lines(source) when is_binary(source) do
    source
    |> String.split("\n")
    |> Enum.flat_map(&split_line_inline_let_in/1)
    |> Enum.join("\n")
  end

  @spec split_line_inline_let_in(line()) :: lines()
  defp split_line_inline_let_in(line) when is_binary(line) do
    trimmed = String.trim(line)

    if Regex.match?(@inline_let_in_line, trimmed) do
      case split_rightmost_inline_let_in(trimmed) do
        {:ok, before, in_expr} ->
          split_line_inline_let_in(before) ++ ["in" | split_line_inline_let_in(in_expr)]

        :error ->
          [line]
      end
    else
      [line]
    end
  end

  @spec split_rightmost_inline_let_in(source()) :: {:ok, source(), source()} | :error
  defp split_rightmost_inline_let_in(line) when is_binary(line) do
    trimmed = String.trim_trailing(line)

    cond do
      String.ends_with?(trimmed, " in") ->
        before = trimmed |> String.slice(0, String.length(trimmed) - 3) |> String.trim_trailing()

        if String.contains?(before, "let ") do
          {:ok, before, ""}
        else
          :error
        end

      true ->
        case :binary.matches(trimmed, " in ") do
          [] ->
            :error

          matches ->
            {pos, len} = List.last(matches)
            before = trimmed |> String.slice(0, pos) |> String.trim_trailing()

            rest_len = String.length(trimmed) - pos - len

            if rest_len < 0 do
              :error
            else
              in_expr =
                trimmed
                |> String.slice(pos + len, rest_len)
                |> String.trim_leading()

              if String.contains?(before, "let ") do
                {:ok, before, in_expr}
              else
                :error
              end
            end
        end
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

  @spec find_rewritable_let_block(lines()) :: let_rewrite_block() | nil
  defp find_rewritable_let_block(lines) when is_list(lines) do
    lines
    |> Enum.with_index()
    |> Enum.find_value(fn {line, index} ->
      cond do
        String.trim(line) == "let" ->
          rest = Enum.drop(lines, index + 1)
          {binding_lines, in_lines} = split_let_lines(rest, [], 1)
          bindings = collect_let_bindings(binding_lines)

          if in_lines != [] and length(bindings) > 1 do
            %{index: index, bindings: bindings, in_lines: in_lines}
          else
            nil
          end

        Regex.match?(~r/^\s*let\s+[a-z][A-Za-z0-9_']*\s*=\s+.+/u, line) ->
          rest = Enum.drop(lines, index + 1)
          first_line_rest = line |> String.trim() |> String.replace_prefix("let ", "")
          first_line = align_first_let_binding_indent(first_line_rest, rest)
          {binding_lines, in_lines} = split_let_lines(rest, [first_line], 1)
          bindings = collect_let_bindings(binding_lines)

          if in_lines != [] and length(bindings) > 1 do
            %{index: index, bindings: bindings, in_lines: in_lines}
          else
            nil
          end

        true ->
          nil
      end
    end)
  end

  @spec align_first_let_binding_indent(String.t(), lines()) :: String.t()
  defp align_first_let_binding_indent(first_line_rest, binding_lines) do
    case infer_let_binding_indent(binding_lines) do
      indent when is_integer(indent) and indent > 0 ->
        String.duplicate(" ", indent) <> first_line_rest

      _ ->
        first_line_rest
    end
  end

  @spec infer_let_binding_indent(lines()) :: non_neg_integer() | nil
  defp infer_let_binding_indent(lines) do
    Enum.find_value(lines, fn line ->
      if let_binding_start_line?(line), do: leading_indent_count(line)
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
    binding_name = "(?:_|[a-z][A-Za-z0-9_]*)"

    Regex.match?(
      ~r/^[a-z][A-Za-z0-9_']*(?:\s+[a-z][A-Za-z0-9_']*|\s+_|\s+\([^\)]*\))*\s*=(?!=)/u,
      trimmed
    ) or
      Regex.match?(
        ~r/^\(\s*#{binding_name}(?:\s*,\s*#{binding_name}){1,2}\s*\)\s*=(?!=)/u,
        trimmed
      ) or
      Regex.match?(
        ~r/^\(\s*[A-Z][A-Za-z0-9_]*(?:\s+[^=()]+)?\s*\)\s*=(?!=)/u,
        trimmed
      )
  end

  @spec normalize(normalized_value()) :: normalized_value()
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
    case find_embedded_case_start(lines) do
      nil ->
        Enum.join(lines, "\n")

      idx ->
        {before, case_and_after} = Enum.split(lines, idx)

        case case_and_after do
          case_lines when is_list(case_lines) and case_lines != [] ->
            {case_header_lines, branches} = split_case_header_lines(case_lines)

            prefix =
              before
              |> Enum.join("\n")
              |> String.trim()

            {branches_text, remaining_lines} = normalize_case_branches(branches)
            case_expr = build_embedded_case_expr(Enum.join(case_header_lines, "\n"), branches_text)
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

  @spec find_embedded_case_start(lines()) :: non_neg_integer() | nil
  defp find_embedded_case_start(lines) when is_list(lines) do
    Enum.find_value(Enum.with_index(lines), fn {line, idx} ->
      trimmed = String.trim(line)

      cond do
        case_header_line?(trimmed) and String.contains?(trimmed, " of") ->
          idx

        case_header_line?(trimmed) ->
          rest = Enum.slice(lines, idx + 1, 40)

          if Enum.any?(rest, fn next_line ->
               t = String.trim(next_line)
               t == "of" or Regex.match?(~r/^of\b/u, t)
             end) do
            idx
          end

        true ->
          nil
      end
    end)
  end

  defp case_header_line?(trimmed) when is_binary(trimmed) do
    String.contains?(trimmed, "case ") or String.contains?(trimmed, "(case") or
      Regex.match?(~r/\bcase\b/u, trimmed)
  end

  @spec split_case_header_lines(lines()) :: {lines(), lines()}
  defp split_case_header_lines([first | rest]) do
    trimmed = String.trim(first)

    if String.contains?(trimmed, " of") do
      {[first], rest}
    else
      case Enum.split_while(rest, fn line ->
             t = String.trim(line)
             t != "of" and not Regex.match?(~r/^of\b/u, t)
           end) do
        {prefix, [of_line | branches]} ->
          {[first | prefix] ++ [of_line], branches}

        {prefix, []} ->
          {[first | prefix], []}
      end
    end
  end

  defp split_case_header_lines([]), do: {[], []}

  @spec normalize_case_branches(lines()) :: {source(), lines()}
  defp normalize_case_branches(lines) when is_list(lines) do
    {items, current, _branch_indent, _let_depth, rest} =
      consume_case_branches(lines, [], nil, nil, 0)

    normalized_items =
      if is_binary(current), do: items ++ [String.trim(current)], else: items

    normalized_items =
      normalized_items
      |> Enum.map(&wrap_branch_case_expression/1)
      |> Enum.map(&normalize_nested_case_in_branch/1)
      |> Enum.map(&wrap_branch_case_expression/1)

    {Enum.join(normalized_items, ";;"), rest}
  end

  # Outer case normalization leaves nested `case ... of` bodies as raw multiline
  # text inside a branch RHS. Re-run case normalization so sibling arms like
  # `( Just _, Err _ )` survive when embedded under a large outer arm body.
  @spec normalize_nested_case_in_branch(source()) :: source()
  defp normalize_nested_case_in_branch(branch) when is_binary(branch) do
    case String.split(branch, "->", parts: 2) do
      [pattern, expr] ->
        trimmed = String.trim(expr)
        reflowed = reflow_inline_case_arms(trimmed)

        normalized =
          if reflowed != trimmed do
            # reflow already expanded ` of\n`, split sibling 3-tuple arms, and
            # parenthesized leaking bodies — re-running normalize_case_source would
            # collapse those arms back onto one line.
            reflowed
          else
            normalize_case_source(trimmed)
          end

        String.trim(pattern) <> " -> " <> normalized

      _ ->
        branch
    end
  end

  @spec reflow_inline_case_arms(source()) :: source()
  defp reflow_inline_case_arms(source) when is_binary(source) do
    if String.contains?(source, ";;") and not String.contains?(source, " of\n") do
      source
      |> expand_case_of_to_newline()
      |> split_triple_case_sibling_arms()
      |> Enum.map(&wrap_triple_case_reflow_fragment/1)
      |> Enum.join("\n")
    else
      source
    end
  end

  @spec split_triple_case_sibling_arms(source()) :: [source()]
  defp split_triple_case_sibling_arms(source) when is_binary(source) do
    source
    |> String.split(~r/;;\s*(?=\(\s*[^,()]+\s*,\s*[^,()]+\s*,\s*[^)]+\)\s*->)/u)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.flat_map(&split_triple_case_wildcard_tail/1)
  end

  # Parenthesize 3-tuple case arm bodies that still contain `;;` so sibling arms
  # are not swallowed by yecc. Only touch triple-case headers/arms — never generic
  # `pattern -> body` lines (nested 2-arm cases must keep their `;;` separators).
  @spec wrap_triple_case_reflow_fragment(source()) :: source()
  defp wrap_triple_case_reflow_fragment(fragment) when is_binary(fragment) do
    fragment
    |> wrap_triple_case_header_first_arm()
    |> wrap_triple_tuple_arm_if_leaking()
  end

  @spec wrap_triple_case_header_first_arm(source()) :: source()
  defp wrap_triple_case_header_first_arm(fragment) when is_binary(fragment) do
    case Regex.run(
           ~r/^(?<prefix>\(?\s*case\s+\(\s*[^)]+\)\s+of\s+)(\(\s*[^,()]+\s*,\s*[^,()]+\s*,\s*[^)]+\)\s*->)\s*(?<body>.*)$/su,
           fragment
         ) do
      [_, prefix, first_arm, body] ->
        prefix <> first_arm <> " " <> wrap_arm_body_if_leaking(body)

      _ ->
        fragment
    end
  end

  @spec wrap_triple_tuple_arm_if_leaking(source()) :: source()
  defp wrap_triple_tuple_arm_if_leaking(fragment) when is_binary(fragment) do
    case Regex.run(
           ~r/^(\(\s*[^,()]+\s*,\s*[^,()]+\s*,\s*[^)]+\)\s*->)\s*(.*)$/su,
           String.trim(fragment)
         ) do
      [_, pattern, body] ->
        pattern <> " " <> wrap_arm_body_if_leaking(body)

      _ ->
        fragment
    end
  end

  @spec wrap_arm_body_if_leaking(source()) :: source()
  defp wrap_arm_body_if_leaking(body) when is_binary(body) do
    trimmed = String.trim(body)

    if arm_body_needs_wrap?(trimmed) do
      "(" <> trimmed <> ")"
    else
      trimmed
    end
  end

  @spec arm_body_needs_wrap?(source()) :: boolean()
  defp arm_body_needs_wrap?(body) when is_binary(body) do
    String.contains?(body, ";;") and
      not (String.starts_with?(body, "(") and paren_balance_outside_string_literals(body) == 0)
  end

  # Pull the triple-case wildcard `_ -> …` off an Err arm fragment. Inner nested
  # cases may also contain `_ ->` arms, so split at the last `;; _ ->` separator.
  @spec split_triple_case_wildcard_tail(source()) :: [source()]
  defp split_triple_case_wildcard_tail(part) when is_binary(part) do
    trimmed = String.trim(part)

    if Regex.match?(~r/^\(\s*[^,()]+\s*,\s*[^,()]+\s*,\s*Err\s+_\s*\)\s*->/u, trimmed) do
      case :binary.matches(part, ";; _ ->") do
        [] ->
          [part]

        matches ->
          {pos, _} = List.last(matches)
          err_part = part |> String.slice(0, pos) |> String.trim()
          wildcard = part |> String.slice(pos + 2, String.length(part)) |> String.trim_leading()
          [err_part, wildcard]
      end
    else
      [part]
    end
  end

  @spec wrap_branch_case_expression(source()) :: source()
  defp wrap_branch_case_expression(branch) when is_binary(branch) do
    case String.split(branch, "->", parts: 2) do
      [pattern, expr] ->
        trimmed_expr = String.trim(expr)

        if String.starts_with?(trimmed_expr, "case ") and String.contains?(trimmed_expr, " of ") do
          String.trim(pattern) <> " -> (" <> trimmed_expr <> ")"
        else
          branch
        end

      _ ->
        branch
    end
  end

  @spec build_embedded_case_expr(source(), source()) :: source()
  defp build_embedded_case_expr(case_header, branches_text)
       when is_binary(case_header) and is_binary(branches_text) do
    branches =
      branches_text
      |> String.trim_leading()
      |> String.replace(~r/^;;\s*/, "")

    header = String.trim_trailing(case_header)

    if String.contains?(header, "++ case ") do
      case String.split(header, "++ case ", parts: 2) do
        [before_append, case_rest] ->
          before_append <> "++ (case " <> case_rest <> " " <> branches <> ")"

        _ ->
          header <> " " <> branches
      end
    else
      header <> " " <> branches
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
      is_binary(current) and is_integer(branch_indent) and indent < branch_indent and
          String.starts_with?(String.trim(line), ",") ->
        {acc, current, branch_indent, let_depth, [line | rest]}

      is_binary(current) and is_integer(branch_indent) and case_branch_start_line?(line) and
          indent < branch_indent ->
        {acc, current, branch_indent, let_depth, [line | rest]}

      is_binary(current) and is_integer(branch_indent) and case_branch_start_line?(line) and
          indent > branch_indent ->
        separator =
          if String.ends_with?(String.trim(current), " of") do
            " "
          else
            " ;; "
          end

        updated = current <> separator <> String.trim(line)
        next_depth = next_let_depth(let_depth, line)
        consume_case_branches(rest, acc, updated, branch_indent, next_depth)

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

      is_binary(current) and let_depth == 0 and case_branch_terminator_line?(line) and
          (is_nil(branch_indent) or indent <= branch_indent) ->
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

    (let_binding_start_line?(line) and not String.starts_with?(trimmed, "let ")) or
      Regex.match?(~r/^in\b/u, trimmed)
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

  @spec maybe_fallback_unsupported(source(), Types.parse_error_reason()) ::
          {:ok, expr()} | {:error, Types.parse_error_reason()}
  defp maybe_fallback_unsupported(source, reason) when is_binary(source) do
    {:error, reason}
  end

  @spec parse_once(source()) :: {:ok, expr()} | {:error, Types.parse_error_reason()}
  defp parse_once(source) when is_binary(source) do
    prepared = prepare_source(source)

    with :ok <- LetLayout.validate(prepared),
         :ok <- validate_source_compat(prepared),
         {:ok, tokens, _line} <- :elm_ex_expr_lexer.string(String.to_charlist(prepared)),
         {:ok, expr} <- :elm_ex_expr_parser.parse(tokens) do
      {:ok, normalize(expr)}
    else
      {:error, {:inline_let_in, line}} -> {:error, LetLayout.parse_error(line)}
      {:error, reason} -> {:error, reason}
      {:error, reason, _line} -> {:error, reason}
    end
  end

  @spec recover_source_for_reason(source(), Types.expr_yecc_error()) :: source() | nil
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

      token when token in [~c"shl", ~c"shr"] ->
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

  @spec normalize_inline_case_branch_separators(source()) :: source()
  defp normalize_inline_case_branch_separators(source) when is_binary(source) do
    if String.contains?(source, "case ") and String.contains?(source, " of") and
         not String.contains?(source, " of\n") do
      Regex.replace(
        ~r/(?<!;)(?<!of);\s*(?=(?:True|False|_|'[^']*'|\"[^\"]*\"|0x[0-9A-Fa-f]+|[0-9]+|\(\)|\[\]|\([^)]+\)|\{[^}]+\}|[A-Z][A-Za-z0-9_.']*|[a-z][A-Za-z0-9_']*)\s*->)/u,
        source,
        ";; "
      )
    else
      source
    end
  end

  @spec normalize_trailing_commas(source()) :: source()
  defp normalize_trailing_commas(source) when is_binary(source) do
    source
    |> String.replace(~r/,\s*\]/u, "]")
    |> String.replace(~r/,\s*\}/u, "}")
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
      ~r/(\bthen\b|\belse\b|\bin\b|==|\/=|>=|<=|>|<|=|->|,|;|\[|\{|\()\s*-\s*([a-z][A-Za-z0-9_.]*|\()/u,
      source,
      "\\1 negate \\2"
    )
  end

  @spec validate_source_compat(source()) :: :ok | {:error, {atom(), atom()}}
  defp validate_source_compat(source) when is_binary(source) do
    scrubbed =
      source
      |> scrub_string_and_char_literals()
      |> scrub_scientific_float_literals()

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

      Regex.match?(~r/(^|[^\w.])0[0-9]+\b(?!\.)/u, scrubbed) ->
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

  @spec scrub_scientific_float_literals(source()) :: source()
  defp scrub_scientific_float_literals(source) when is_binary(source) do
    Regex.replace(~r/\b[0-9]+(?:\.[0-9]+)?[eE][+\-]?[0-9]+\b/u, source, "0.0")
  end
end
