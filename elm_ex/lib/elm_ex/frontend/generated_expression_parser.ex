defmodule ElmEx.Frontend.GeneratedExpressionParser do
  @moduledoc """
  Generated expression parser adapter based on leex/yecc artifacts.

  Multiline Elm layout is tokenized by `ElmEx.Frontend.ExprLayoutLexer` when the
  source has physical newlines and no legacy `;;` case-arm separators (default).
  Set `Application.put_env(:elm_ex, :expr_layout_lexer, false)` to use the
  whitespace-skipping Leex path with `ExprLayout.normalize/1` instead.

  See `docs/expr_layout_lexer.md` for architecture and token semantics.
  """

  alias ElmEx.Frontend.AstContract.Types, as: AstTypes
  alias ElmEx.Frontend.ExprLayoutLexer
  alias ElmEx.Frontend.{Layout, LetLayout}
  alias ElmEx.Types

  @typep source() :: String.t()
  @typep line() :: String.t()
  @typep expr() :: AstTypes.expr()
  @typep normalized_value() :: AstTypes.expr() | list() | String.t() | number() | boolean() | nil | atom()

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
  defp prepare_source(source) when is_binary(source) do
    source
    |> prepare_source_core()
    |> maybe_normalize_for_parser()
  end

  @spec maybe_normalize_for_parser(source()) :: source()
  defp maybe_normalize_for_parser(prepared) do
    if layout_lexer_enabled?() and layout_lexer_eligible?(prepared) do
      prepared
    else
      ElmEx.Frontend.ExprLayout.normalize(prepared)
    end
  end

  @spec prepare_source_core(source()) :: source()
  defp prepare_source_core(source) when is_binary(source) do
    source
    |> trim_prepared_source()
    |> normalize_multiline_strings()
    |> strip_block_comments()
    |> strip_line_comments()
    |> collapse_standalone_record_update_bars()
    |> strip_local_type_annotations()
    |> strip_trailing_semicolons()
    |> normalize_nested_compose_sections()
    |> normalize_compose_source()
    |> fix_record_update_bar_paren_glitch()
    |> normalize_minus_numeric_source()
    |> normalize_trailing_commas()
    |> close_unbalanced_brackets_before_final_pipe()
    |> close_unbalanced_parens()
  end

  # Multiline snippets (heredocs, pasted blocks) must keep uniform relative indent.
  # `String.trim/1` only strips leading whitespace from the first line and breaks `in`
  # alignment; blank-line trim + uniform dedent preserves Elm layout.
  @spec trim_prepared_source(source()) :: source()
  defp trim_prepared_source(source) when is_binary(source) do
    if String.contains?(source, "\n") do
      source
      |> String.trim_trailing()
      |> String.replace(~r/^\s*\n/u, "")
      |> Layout.dedent_uniform_leading_whitespace()
    else
      String.trim(source)
    end
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

      String.contains?(line, "=") ->
        drop_local_type_annotation_lines(rest, [line | acc], :keep)

      true ->
        drop_local_type_annotation_lines(rest, acc, :dropping)
    end
  end

  defp drop_local_type_annotation_lines([line | rest], acc, :keep) do
    cond do
      Regex.match?(~r/^\s*[a-z][A-Za-z0-9_']*\s*:(?!:)\s*.+$/u, line) ->
        drop_local_type_annotation_lines(rest, acc, :keep)

      Regex.match?(~r/^\s*[a-z][A-Za-z0-9_']*\s*:(?!:)\s*$/u, line) ->
        drop_local_type_annotation_lines(rest, acc, :dropping)

      true ->
        drop_local_type_annotation_lines(rest, [line | acc], :keep)
    end
  end

  @spec normalize_compose_source(source()) :: source()
  defp normalize_compose_source(source) when is_binary(source) do
    Regex.replace(
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

  @spec close_unbalanced_parens(source()) :: source()
  defp close_unbalanced_parens(source) when is_binary(source) do
    # Layout normalization sometimes wraps large branches in parentheses; when a rewrite
    # drops a closing paren near the end, yecc reports an EOF parse error. Recover by
    # appending up to a small number of ')' to restore balance.
    diff = paren_balance_outside_string_literals(source)

    cond do
      diff > 0 and diff <= 3 ->
        source <> String.duplicate(")", diff)

      diff < 0 and diff >= -3 ->
        String.slice(source, 0, byte_size(source) + diff)

      true ->
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

  @spec leading_indent_count(line()) :: non_neg_integer()
  defp leading_indent_count(line) when is_binary(line) do
    line
    |> String.graphemes()
    |> Enum.take_while(&(&1 == " " or &1 == "\t"))
    |> length()
  end

  @spec fix_record_update_bar_paren_glitch(source()) :: source()
  defp fix_record_update_bar_paren_glitch(source) when is_binary(source) do
    # After aggressive case/layout normalization, a record-update bar line that used
    # to be `| -- comment` can end up as `|) field = ...` (the `)` belongs to an
    # outer tuple paren, not the record update). This rewrite is conservative:
    # only fix the exact `|)` sequence when it is immediately followed by a field.
    Regex.replace(~r/\|\)\s*([a-z][A-Za-z0-9_']*\s*=)/u, source, "| \\1")
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

  @spec parse_once(source()) :: {:ok, expr()} | {:error, Types.parse_error_reason()}
  defp parse_once(source) when is_binary(source) do
    parse_prepared(prepare_source(source))
  end

  @spec parse_prepared(source(), keyword()) :: {:ok, expr()} | {:error, Types.parse_error_reason()}
  defp parse_prepared(prepared, opts \\ []) do
    force_layout? = Keyword.get(opts, :force_layout_lexer, false)

    with :ok <- LetLayout.validate(prepared),
         :ok <- validate_source_compat(prepared),
         {:ok, tokens, _line} <- tokenize_prepared(prepared, force_layout?),
         {:ok, expr} <- :elm_ex_expr_parser.parse(tokens) do
      {:ok, normalize(expr)}
    else
      {:error, {:inline_let_in, line}} -> {:error, LetLayout.parse_error(line)}
      {:error, reason} -> {:error, reason}
      {:error, reason, _line} -> {:error, reason}
    end
  end

  @spec tokenize_prepared(source(), boolean()) ::
          {:ok, [term()], pos_integer()} | {:error, term()}
  defp tokenize_prepared(prepared, true), do: ExprLayoutLexer.tokenize(prepared)

  defp tokenize_prepared(prepared, false), do: tokenize_for_parser(prepared)

  # Multiline sources without legacy `;;` arm separators use the layout lexer.
  # Normalized `;;` fragments and single-line sources keep the whitespace-skipping Leex path.
  @spec tokenize_for_parser(source()) :: {:ok, [term()], pos_integer()} | {:error, term()}
  defp tokenize_for_parser(prepared) do
    if layout_lexer_enabled?() and layout_lexer_eligible?(prepared) do
      ExprLayoutLexer.tokenize(prepared)
    else
      :elm_ex_expr_lexer.string(String.to_charlist(prepared))
    end
  end

  defp layout_lexer_enabled? do
    Application.get_env(:elm_ex, :expr_layout_lexer, true)
  end

  defp layout_lexer_eligible?(prepared) do
    String.contains?(prepared, "\n") and not String.contains?(prepared, ";;") and
      LetLayout.validate(prepared) == :ok
  end

  @doc """
  Parse expression source using the layout lexer directly (no `ExprLayout.normalize/1`).

  Prefer `parse/1` for normal use — it selects layout lexing or normalize automatically.
  This entry point always tokenizes with `ExprLayoutLexer` and is kept for tests and
  tools that must bypass the legacy normalize path.
  """
  @spec parse_with_layout_lexer(String.t()) :: {:ok, expr()} | {:error, Types.parse_error_reason()}
  def parse_with_layout_lexer(source) when is_binary(source) do
    source
    |> prepare_source_core()
    |> parse_prepared(force_layout_lexer: true)
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

  @spec unbalanced_multiline_string_delimiter?(source()) :: boolean()
  defp unbalanced_multiline_string_delimiter?(source) when is_binary(source) do
    occurrences = Regex.scan(~r/\"\"\"/u, source) |> length()
    rem(occurrences, 2) == 1
  end

  @spec normalize_trailing_commas(source()) :: source()
  defp normalize_trailing_commas(source) when is_binary(source) do
    source
    |> String.replace(~r/,\s*\]/u, "]")
    |> String.replace(~r/,\s*\}/u, "}")
  end

  @spec normalize_minus_numeric_source(source()) :: source()
  defp normalize_minus_numeric_source(source) when is_binary(source) do
    {masked, literals} = mask_string_and_char_literals(source)

    masked
    |> normalize_leading_negative_hex()
    |> normalize_leading_unary_minus()
    |> normalize_contextual_unary_minus()
    |> normalize_inline_numeric_subtraction()
    |> restore_masked_string_and_char_literals(literals)
  end

  @string_or_char_literal ~r/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/u
  @masked_literal_prefix "\u{E0000}"
  @masked_literal_suffix "\u{E0001}"

  @spec mask_string_and_char_literals(source()) :: {source(), [source()]}
  defp mask_string_and_char_literals(source) when is_binary(source) do
    literals = Regex.scan(@string_or_char_literal, source, return: :binary) |> List.flatten()

    masked =
      Enum.reduce(Enum.with_index(literals), source, fn {literal, index}, acc ->
        placeholder = "#{@masked_literal_prefix}#{index}#{@masked_literal_suffix}"
        String.replace(acc, literal, placeholder, global: false)
      end)

    {masked, literals}
  end

  @spec restore_masked_string_and_char_literals(source(), [source()]) :: source()
  defp restore_masked_string_and_char_literals(source, literals) when is_list(literals) do
    Enum.reduce(Enum.with_index(literals), source, fn {literal, index}, acc ->
      placeholder = "#{@masked_literal_prefix}#{index}#{@masked_literal_suffix}"
      String.replace(acc, placeholder, literal)
    end)
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

  @spec maybe_fallback_unsupported(source(), Types.parse_error_reason()) ::
          {:ok, expr()} | {:error, Types.parse_error_reason()}
  defp maybe_fallback_unsupported(_source, reason), do: {:error, reason}
end
