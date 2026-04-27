defmodule Ide.Tokenizer do
  @moduledoc """
  Tokenization seam for editor syntax highlighting and diagnostics.
  """
  @dialyzer :no_match
  alias Ide.Formatter.Semantics.HeaderMetadata
  alias Ide.Diagnostics.TokenizerParserMapper

  @keywords ~w(
    module exposing import as type alias let in if then else case of where port
  )

  @type token :: %{
          text: String.t(),
          class: String.t(),
          line: integer(),
          column: integer(),
          length: integer()
        }

  @type diagnostic :: %{
          required(:severity) => String.t(),
          required(:source) => String.t(),
          required(:message) => String.t(),
          required(:line) => integer() | nil,
          required(:column) => integer() | nil,
          optional(:end_line) => integer() | nil,
          optional(:end_column) => integer() | nil,
          optional(:catalog_id) => atom(),
          optional(:catalog_version) => String.t(),
          optional(:elm_title) => String.t(),
          optional(:elm_source_title) => String.t(),
          optional(:elm_hint) => String.t(),
          optional(:elm_example) => String.t(),
          optional(:elm_span_semantics) => atom()
        }

  @type parser_payload :: %{
          diagnostics: [map()],
          metadata: HeaderMetadata.metadata(),
          source_hash: integer(),
          fallback?: boolean()
        }

  @doc """
  Tokenizes source text into lightweight syntax classes and diagnostics.
  """
  @spec tokenize(String.t(), keyword()) :: %{
          tokens: [token()],
          diagnostics: [diagnostic()],
          formatter_parser_payload: parser_payload() | nil
        }
  def tokenize(source, opts \\ []) when is_binary(source) do
    {tokens, diagnostics} = scan(source, 1, 1, [], [])
    ordered_tokens = Enum.reverse(tokens)
    ordered_diagnostics = Enum.reverse(diagnostics)
    delimiter_diagnostics = delimiter_diagnostics(ordered_tokens)
    field_label_diagnostics = field_label_diagnostics(ordered_tokens)
    base_diagnostics = ordered_diagnostics ++ delimiter_diagnostics ++ field_label_diagnostics

    case Keyword.get(opts, :mode, :fast) do
      :compiler ->
        case compiler_lex(source) do
          {:ok, payload} ->
            classed_tokens =
              ordered_tokens
              |> apply_elmc_classes(payload.tokens)
              |> normalize_qualified_value_identifiers()
              |> mark_dot_access_fields()
              |> mark_record_field_identifiers()
              |> mark_type_annotation_operators()
              |> mark_type_annotation_record_extension_pipes()
              |> mark_type_annotation_grouping_operators()
              |> mark_type_declaration_operators()
              |> mark_type_declaration_identifiers()
              |> mark_type_alias_head_identifiers()
              |> mark_type_alias_record_identifiers()
              |> mark_type_alias_field_colons()
              |> mark_type_alias_operators()
              |> mark_type_alias_identifiers()
              |> mark_type_annotation_identifiers()

            %{
              tokens: classed_tokens,
              diagnostics:
                base_diagnostics ++ normalize_compiler_diagnostics(payload.diagnostics, source),
              formatter_parser_payload: payload.parser_payload
            }

          {:error, %{line: line, reason: reason, diagnostics: diagnostics}} ->
            %{
              tokens: ordered_tokens,
              diagnostics:
                base_diagnostics ++
                  normalize_compiler_diagnostics(diagnostics, source) ++
                  [compiler_diagnostic(line, reason, source)],
              formatter_parser_payload: maybe_formatter_parser_payload(source)
            }

          {:error, reason} ->
            %{
              tokens: ordered_tokens,
              diagnostics:
                base_diagnostics ++ [compiler_diagnostic(nil, inspect(reason), source)],
              formatter_parser_payload: maybe_formatter_parser_payload(source)
            }
        end

      _ ->
        %{
          tokens:
            ordered_tokens
            |> normalize_qualified_value_identifiers()
            |> mark_dot_access_fields()
            |> mark_record_field_identifiers()
            |> mark_type_annotation_operators()
            |> mark_type_annotation_record_extension_pipes()
            |> mark_type_annotation_grouping_operators()
            |> mark_type_declaration_operators()
            |> mark_type_declaration_identifiers()
            |> mark_type_alias_head_identifiers()
            |> mark_type_alias_record_identifiers()
            |> mark_type_alias_field_colons()
            |> mark_type_alias_operators()
            |> mark_type_alias_identifiers()
            |> mark_type_annotation_identifiers(),
          diagnostics: base_diagnostics,
          formatter_parser_payload: maybe_formatter_parser_payload(source)
        }
    end
  end

  @spec normalize_qualified_value_identifiers(term()) :: [token()]
  defp normalize_qualified_value_identifiers(tokens) when is_list(tokens) do
    Enum.map(tokens, fn token ->
      if qualified_value_identifier_token?(token) do
        %{token | class: "identifier"}
      else
        token
      end
    end)
  end

  @spec qualified_value_identifier_token?(term()) :: boolean()
  defp qualified_value_identifier_token?(%{class: "type_identifier", text: text})
       when is_binary(text) do
    case String.split(text, ".", trim: true) do
      [_single] ->
        false

      segments ->
        case List.last(segments) do
          <<first::utf8, _::binary>> -> first in ?a..?z or first == ?_
          _ -> false
        end
    end
  end

  defp qualified_value_identifier_token?(_), do: false

  @spec mark_dot_access_fields(term()) :: [token()]
  defp mark_dot_access_fields(tokens) when is_list(tokens) do
    {marked, _state} =
      Enum.map_reduce(tokens, %{pending_dot: nil, prev_non_trivia: nil}, fn token, state ->
        pending_dot = state.pending_dot
        prev_non_trivia = state.prev_non_trivia

        cond do
          is_map(pending_dot) and token.class == "identifier" and token.line == pending_dot.line and
              token.column == pending_dot.column + 1 ->
            marked = %{token | class: "field_identifier"}
            {marked, %{pending_dot: nil, prev_non_trivia: marked}}

          trivia_token?(token) ->
            {token, %{state | pending_dot: nil}}

          token.class == "operator" and token.text == "." and
              dot_access_left_token?(prev_non_trivia) ->
            {token,
             %{pending_dot: %{line: token.line, column: token.column}, prev_non_trivia: token}}

          true ->
            {token, %{pending_dot: nil, prev_non_trivia: token}}
        end
      end)

    marked
  end

  @spec dot_access_left_token?(term()) :: boolean()
  defp dot_access_left_token?(%{class: klass})
       when klass in ["identifier", "field_identifier"],
       do: true

  defp dot_access_left_token?(%{class: "operator", text: text}) when text in [")", "]", "}"],
    do: true

  defp dot_access_left_token?(_), do: false

  @spec scan(term(), term(), term(), term(), term()) :: {[token()], [diagnostic()]}
  defp scan("", _line, _column, tokens, diagnostics), do: {tokens, diagnostics}

  defp scan(<<"--", rest::binary>>, line, column, tokens, diagnostics) do
    {comment, tail} = take_until_newline(rest, "--")
    len = String.length(comment)
    token = %{text: comment, class: "comment", line: line, column: column, length: len}
    {next_line, next_column} = advance(comment, line, column)
    scan(tail, next_line, next_column, [token | tokens], diagnostics)
  end

  defp scan(<<"{-", rest::binary>>, line, column, tokens, diagnostics) do
    {comment, tail, terminated?} = take_block_comment(rest, "{-", 1)
    len = String.length(comment)
    token = %{text: comment, class: "comment", line: line, column: column, length: len}
    {next_line, next_column} = advance(comment, line, column)

    diagnostics =
      if terminated? do
        diagnostics
      else
        [
          unterminated_token_diagnostic(:block_comment, line, column, next_line, next_column)
          | diagnostics
        ]
      end

    scan(tail, next_line, next_column, [token | tokens], diagnostics)
  end

  defp scan(<<"\"\"\"", rest::binary>>, line, column, tokens, diagnostics) do
    {string_text, tail, terminated?} = take_triple_string(rest, "")
    token_text = "\"\"\"" <> string_text
    len = String.length(token_text)
    token = %{text: token_text, class: "string", line: line, column: column, length: len}
    {next_line, next_column} = advance(token_text, line, column)

    diagnostics =
      if terminated? do
        string_literal_diagnostics(token_text, line, column) ++ diagnostics
      else
        [
          unterminated_token_diagnostic(
            :multiline_string_literal,
            line,
            column,
            next_line,
            next_column
          )
          | diagnostics
        ]
      end

    scan(tail, next_line, next_column, [token | tokens], diagnostics)
  end

  defp scan(<<"\"", rest::binary>>, line, column, tokens, diagnostics) do
    {string_text, tail, terminated?} = take_string(rest, "")
    token_text = "\"" <> string_text
    len = String.length(token_text)
    token = %{text: token_text, class: "string", line: line, column: column, length: len}
    {next_line, next_column} = advance(token_text, line, column)

    diagnostics =
      if terminated? do
        string_literal_diagnostics(token_text, line, column) ++ diagnostics
      else
        [
          unterminated_token_diagnostic(:string_literal, line, column, next_line, next_column)
          | diagnostics
        ]
      end

    scan(tail, next_line, next_column, [token | tokens], diagnostics)
  end

  defp scan(<<"'", rest::binary>>, line, column, tokens, diagnostics) do
    {char_text, tail, valid?} = take_char_literal(rest, "")
    token_text = "'" <> char_text
    len = String.length(token_text)
    token = %{text: token_text, class: "string", line: line, column: column, length: len}
    {next_line, next_column} = advance(token_text, line, column)

    diagnostics =
      if valid? do
        diagnostics
      else
        diagnostic =
          if single_quoted_string_like?(token_text) do
            TokenizerParserMapper.needs_double_quotes(
              line,
              column,
              "The following string uses single quotes. Please switch to double quotes."
            )
          else
            TokenizerParserMapper.invalid_char_literal(line, column)
          end

        [
          diagnostic
          | diagnostics
        ]
      end

    scan(tail, next_line, next_column, [token | tokens], diagnostics)
  end

  defp scan(<<char::utf8, _::binary>> = input, line, column, tokens, diagnostics)
       when char in ?0..?9 do
    {num, tail} = take_number_literal(input)
    len = String.length(num)
    token = %{text: num, class: "number", line: line, column: column, length: len}
    {next_line, next_column} = advance(num, line, column)
    diagnostics = number_literal_diagnostics(input, num, tail, line, column) ++ diagnostics
    scan(tail, next_line, next_column, [token | tokens], diagnostics)
  end

  defp scan(<<char::utf8, _::binary>> = input, line, column, tokens, diagnostics)
       when char >= ?A and char <= ?Z do
    {word, tail} = take_while(input, &upper_identifier_char?/1)
    len = String.length(word)
    token = %{text: word, class: "type_identifier", line: line, column: column, length: len}
    {next_line, next_column} = advance(word, line, column)
    scan(tail, next_line, next_column, [token | tokens], diagnostics)
  end

  defp scan(<<char::utf8, _::binary>> = input, line, column, tokens, diagnostics)
       when (char >= ?a and char <= ?z) or char == ?_ do
    {word, tail} = take_while(input, &lower_identifier_char?/1)
    klass = if word in @keywords, do: "keyword", else: "identifier"
    len = String.length(word)
    token = %{text: word, class: klass, line: line, column: column, length: len}
    {next_line, next_column} = advance(word, line, column)
    scan(tail, next_line, next_column, [token | tokens], diagnostics)
  end

  defp scan(<<".", char::utf8, rest::binary>> = input, line, column, tokens, diagnostics)
       when (char >= ?a and char <= ?z) or char == ?_ do
    if direct_field_accessor_allowed?(tokens, line, column) do
      {field, tail} = take_field_accessor(input)
      len = String.length(field)
      token = %{text: field, class: "field_identifier", line: line, column: column, length: len}
      {next_line, next_column} = advance(field, line, column)
      scan(tail, next_line, next_column, [token | tokens], diagnostics)
    else
      scan_operator(".", <<char::utf8, rest::binary>>, line, column, tokens, diagnostics)
    end
  end

  defp scan(<<char::utf8, _::binary>> = input, line, column, tokens, diagnostics)
       when char in [?\s, ?\t, ?\n, ?\r] do
    {ws, tail} = take_while(input, &(&1 in [?\s, ?\t, ?\n, ?\r]))
    len = String.length(ws)
    token = %{text: ws, class: "whitespace", line: line, column: column, length: len}
    {next_line, next_column} = advance(ws, line, column)
    scan(tail, next_line, next_column, [token | tokens], diagnostics)
  end

  defp scan(<<"`", rest::binary>>, line, column, tokens, diagnostics) do
    case take_backtick_operator(rest, "") do
      {:ok, op_text, tail} ->
        token_text = "`" <> op_text <> "`"

        token = %{
          text: token_text,
          class: "operator",
          line: line,
          column: column,
          length: String.length(token_text)
        }

        scan(tail, line, column + String.length(token_text), [token | tokens], diagnostics)

      :error ->
        scan_operator("`", rest, line, column, tokens, diagnostics)
    end
  end

  defp scan(<<"(.", char::utf8, rest::binary>>, line, column, tokens, diagnostics)
       when (char >= ?a and char <= ?z) or char == ?_ do
    case take_parenthesized_field_accessor(<<char::utf8, rest::binary>>, "") do
      {:ok, field_inner, tail} ->
        token_text = "(." <> field_inner <> ")"

        token = %{
          text: token_text,
          class: "field_identifier",
          line: line,
          column: column,
          length: String.length(token_text)
        }

        scan(tail, line, column + String.length(token_text), [token | tokens], diagnostics)

      :error ->
        scan_operator("(", <<".", char::utf8, rest::binary>>, line, column, tokens, diagnostics)
    end
  end

  defp scan(<<"(", rest::binary>>, line, column, tokens, diagnostics) do
    case take_parenthesized_field_accessor_with_ws(rest) do
      {:ok, accessor_text, tail} ->
        token_text = "(" <> accessor_text

        token = %{
          text: token_text,
          class: "field_identifier",
          line: line,
          column: column,
          length: String.length(token_text)
        }

        {next_line, next_column} = advance(token_text, line, column)
        scan(tail, next_line, next_column, [token | tokens], diagnostics)

      :error ->
        case take_operator_section_with_ws(rest) do
          {:ok, op_text, tail} ->
            token_text = "(" <> op_text

            token = %{
              text: token_text,
              class: "operator",
              line: line,
              column: column,
              length: String.length(token_text)
            }

            {next_line, next_column} = advance(token_text, line, column)
            scan(tail, next_line, next_column, [token | tokens], diagnostics)

          :error ->
            case take_operator_section(rest, "") do
              {:ok, op_inner, tail} ->
                token_text = "(" <> op_inner <> ")"

                token = %{
                  text: token_text,
                  class: "operator",
                  line: line,
                  column: column,
                  length: String.length(token_text)
                }

                scan(
                  tail,
                  line,
                  column + String.length(token_text),
                  [token | tokens],
                  diagnostics
                )

              :error ->
                scan_operator("(", rest, line, column, tokens, diagnostics)
            end
        end
    end
  end

  defp scan(<<"::", rest::binary>>, line, column, tokens, diagnostics),
    do: scan_operator("::", rest, line, column, tokens, diagnostics)

  defp scan(<<char::utf8, _::binary>> = input, line, column, tokens, diagnostics)
       when char in [?!, ?#, ?$, ?%, ?&, ?*, ?+, ?-, ?., ?/, ?:, ?<, ?=, ?>, ?@, ?^, ?|, ?~] do
    {op, tail} = take_while(input, &operator_run_char?/1)

    case split_compact_field_accessor_operator(op, tail, tokens, line, column) do
      {:split, op_prefix, next_input} ->
        scan_operator(op_prefix, next_input, line, column, tokens, diagnostics)

      :no_split ->
        scan_operator(op, tail, line, column, tokens, diagnostics)
    end
  end

  defp scan(<<char::utf8, rest::binary>>, line, column, tokens, diagnostics) do
    text = <<char::utf8>>
    token = %{text: text, class: "operator", line: line, column: column, length: 1}
    scan(rest, line, column + 1, [token | tokens], diagnostics)
  end

  @spec scan_operator(term(), term(), term(), term(), term(), term()) ::
          {[token()], [diagnostic()]}
  defp scan_operator(text, rest, line, column, tokens, diagnostics) do
    token = %{
      text: text,
      class: "operator",
      line: line,
      column: column,
      length: String.length(text)
    }

    scan(rest, line, column + String.length(text), [token | tokens], diagnostics)
  end

  @spec unterminated_token_diagnostic(term(), term(), term(), term(), term()) :: diagnostic()
  defp unterminated_token_diagnostic(kind, line, column, next_line, next_column) do
    eof_column = max(next_column - 1, 1)

    case kind do
      :block_comment ->
        TokenizerParserMapper.unterminated_block_comment(line, column, next_line, eof_column)

      :multiline_string_literal ->
        TokenizerParserMapper.unterminated_multiline_string(line, column, next_line, eof_column)

      _ ->
        TokenizerParserMapper.unterminated_string(line, column, next_line, eof_column)
    end
  end

  @spec single_quoted_string_like?(term()) :: boolean()
  defp single_quoted_string_like?(token_text) when is_binary(token_text) do
    String.starts_with?(token_text, "'") and
      String.ends_with?(token_text, "'") and
      String.length(token_text) > 3 and
      not String.contains?(token_text, "\n") and
      not String.contains?(token_text, "\r")
  end

  @spec string_literal_diagnostics(term(), term(), term()) :: [diagnostic()]
  defp string_literal_diagnostics(token_text, line, column) when is_binary(token_text) do
    unknown_escape_diagnostics(token_text, line, column) ++
      bad_unicode_escape_diagnostics(token_text, line, column)
  end

  @spec unknown_escape_diagnostics(term(), term(), term()) :: [diagnostic()]
  defp unknown_escape_diagnostics(token_text, line, column) do
    Regex.scan(~r/\\([^nrt"'\\u])/, token_text, return: :index)
    |> Enum.map(fn [{idx, _len}, {cap_idx, cap_len}] ->
      escape = String.slice(token_text, cap_idx, cap_len)
      {diag_line, diag_col} = offset_to_position(token_text, line, column, idx)
      TokenizerParserMapper.unknown_escape(diag_line, diag_col, escape)
    end)
  end

  @spec bad_unicode_escape_diagnostics(term(), term(), term()) :: [diagnostic()]
  defp bad_unicode_escape_diagnostics(token_text, line, column) do
    malformed_prefix =
      Regex.scan(~r/\\u(?!\{)/, token_text, return: :index)
      |> Enum.map(fn [{idx, _len}] ->
        {diag_line, diag_col} = offset_to_position(token_text, line, column, idx)

        TokenizerParserMapper.bad_unicode_escape(
          diag_line,
          diag_col,
          "I ran into an invalid Unicode escape."
        )
      end)

    malformed_body =
      Regex.scan(~r/\\u\{([^}]*)\}/, token_text, return: :index)
      |> Enum.flat_map(fn [{idx, _len}, {body_idx, body_len}] ->
        body = String.slice(token_text, body_idx, body_len)
        {diag_line, diag_col} = offset_to_position(token_text, line, column, idx)

        cond do
          body == "" ->
            [
              TokenizerParserMapper.bad_unicode_escape(
                diag_line,
                diag_col,
                "Every code point needs at least four digits."
              )
            ]

          String.length(body) < 4 ->
            [
              TokenizerParserMapper.bad_unicode_escape(
                diag_line,
                diag_col,
                "Every code point needs at least four digits."
              )
            ]

          not Regex.match?(~r/^[0-9a-fA-F]+$/, body) ->
            [
              TokenizerParserMapper.bad_unicode_escape(
                diag_line,
                diag_col,
                "I ran into an invalid Unicode escape."
              )
            ]

          not valid_unicode_scalar_hex?(body) ->
            [
              TokenizerParserMapper.bad_unicode_escape(
                diag_line,
                diag_col,
                "This is not a valid code point."
              )
            ]

          true ->
            []
        end
      end)

    malformed_prefix ++ malformed_body
  end

  @spec number_literal_diagnostics(term(), term(), term(), term(), term()) :: [diagnostic()]
  defp number_literal_diagnostics(input, num, tail, line, column)
       when is_binary(input) and is_binary(num) and is_binary(tail) do
    diagnostics = []

    diagnostics =
      if (String.starts_with?(input, "0x") or String.starts_with?(input, "0X")) and num == "0" do
        [
          TokenizerParserMapper.weird_hexidecimal(
            line,
            column,
            "I was expecting hexadecimal digits after the 0x prefix."
          )
          | diagnostics
        ]
      else
        diagnostics
      end

    diagnostics =
      if Regex.match?(~r/^0[0-9]+$/, num) do
        [
          TokenizerParserMapper.leading_zeros(
            line,
            column,
            "This number has extra leading zeros."
          )
          | diagnostics
        ]
      else
        diagnostics
      end

    diagnostics =
      if (String.starts_with?(tail, "e") or String.starts_with?(tail, "E")) and
           not String.contains?(num, "e") and
           not String.contains?(num, "E") do
        [
          TokenizerParserMapper.weird_number(
            line,
            column,
            "I saw an exponent marker but the number is incomplete."
          )
          | diagnostics
        ]
      else
        diagnostics
      end

    diagnostics
  end

  @spec offset_to_position(term(), term(), term(), term()) :: {integer(), integer()}
  defp offset_to_position(text, start_line, start_column, offset)
       when is_binary(text) and is_integer(start_line) and is_integer(start_column) and
              is_integer(offset) do
    prefix = String.slice(text, 0, max(offset, 0))
    lines = String.split(prefix, "\n", trim: false)

    case lines do
      [single] ->
        {start_line, start_column + String.length(single)}

      _ ->
        {start_line + length(lines) - 1, String.length(List.last(lines)) + 1}
    end
  end

  @spec take_until_newline(term(), term()) :: {String.t(), String.t()}
  defp take_until_newline("", acc), do: {acc, ""}

  defp take_until_newline(<<"\n", rest::binary>>, acc), do: {acc, "\n" <> rest}

  defp take_until_newline(<<char::utf8, rest::binary>>, acc),
    do: take_until_newline(rest, acc <> <<char::utf8>>)

  @spec take_block_comment(term(), term(), term()) :: {String.t(), String.t(), boolean()}
  defp take_block_comment("", acc, _depth), do: {acc, "", false}

  defp take_block_comment(<<"{-", rest::binary>>, acc, depth),
    do: take_block_comment(rest, acc <> "{-", depth + 1)

  defp take_block_comment(<<"-}", rest::binary>>, acc, 1), do: {acc <> "-}", rest, true}

  defp take_block_comment(<<"-}", rest::binary>>, acc, depth),
    do: take_block_comment(rest, acc <> "-}", depth - 1)

  defp take_block_comment(<<char::utf8, rest::binary>>, acc, depth),
    do: take_block_comment(rest, acc <> <<char::utf8>>, depth)

  @spec take_triple_string(term(), term()) :: {String.t(), String.t(), boolean()}
  defp take_triple_string("", acc), do: {acc, "", false}
  defp take_triple_string(<<"\"\"\"", rest::binary>>, acc), do: {acc <> "\"\"\"", rest, true}

  defp take_triple_string(<<char::utf8, rest::binary>>, acc),
    do: take_triple_string(rest, acc <> <<char::utf8>>)

  @spec take_string(term(), term()) :: {String.t(), String.t(), boolean()}
  defp take_string("", acc), do: {acc, "", false}

  defp take_string(<<"\\", c::utf8, rest::binary>>, acc),
    do: take_string(rest, acc <> "\\" <> <<c::utf8>>)

  defp take_string(<<"\"", rest::binary>>, acc), do: {acc <> "\"", rest, true}
  defp take_string(<<"\r\n", rest::binary>>, acc), do: {acc <> "\r\n", rest, false}
  defp take_string(<<"\n", rest::binary>>, acc), do: {acc <> "\n", rest, false}
  defp take_string(<<"\r", rest::binary>>, acc), do: {acc <> "\r", rest, false}

  defp take_string(<<char::utf8, rest::binary>>, acc),
    do: take_string(rest, acc <> <<char::utf8>>)

  @spec take_char_literal(term(), term()) :: {String.t(), String.t(), boolean()}
  defp take_char_literal("", acc), do: {acc, "", false}

  defp take_char_literal(<<"\\u{", rest::binary>>, "") do
    case take_unicode_char_escape(rest, "") do
      {:ok, body, tail} ->
        {"\\u{" <> body <> "}'", tail, true}

      :error ->
        take_char_literal(rest, "\\u{")
    end
  end

  defp take_char_literal(<<"\\", c::utf8, "'", rest::binary>>, "") do
    {"\\" <> <<c::utf8>> <> "'", rest, true}
  end

  defp take_char_literal(<<c::utf8, "'", rest::binary>>, "") do
    {<<c::utf8>> <> "'", rest, true}
  end

  defp take_char_literal(<<"'", rest::binary>>, acc) do
    {acc <> "'", rest, false}
  end

  defp take_char_literal(<<char::utf8, rest::binary>>, acc) do
    # keep consuming until we either see a valid close pattern or hit EOF/newline
    if char in [?\n, ?\r] do
      {acc <> <<char::utf8>>, rest, false}
    else
      take_char_literal(rest, acc <> <<char::utf8>>)
    end
  end

  @spec take_unicode_char_escape(term(), term()) :: {:ok, String.t(), String.t()} | :error
  defp take_unicode_char_escape(<<"}", "'", tail::binary>>, acc) when acc != "" do
    if valid_unicode_scalar_hex?(acc) do
      {:ok, acc, tail}
    else
      :error
    end
  end

  defp take_unicode_char_escape(<<char::utf8, rest::binary>>, acc) when char in ?0..?9,
    do: take_unicode_char_escape(rest, acc <> <<char::utf8>>)

  defp take_unicode_char_escape(<<char::utf8, rest::binary>>, acc) when char in ?a..?f,
    do: take_unicode_char_escape(rest, acc <> <<char::utf8>>)

  defp take_unicode_char_escape(<<char::utf8, rest::binary>>, acc) when char in ?A..?F,
    do: take_unicode_char_escape(rest, acc <> <<char::utf8>>)

  defp take_unicode_char_escape(_, _acc), do: :error

  @spec valid_unicode_scalar_hex?(term()) :: boolean()
  defp valid_unicode_scalar_hex?(hex) when is_binary(hex) do
    if byte_size(hex) > 6 do
      false
    else
      case Integer.parse(hex, 16) do
        {codepoint, ""} ->
          codepoint <= 0x10FFFF and codepoint not in 0xD800..0xDFFF

        _ ->
          false
      end
    end
  end

  @spec take_while(term(), term()) :: {String.t(), String.t()}
  defp take_while(binary, predicate), do: take_while(binary, predicate, "")

  @spec take_field_accessor(term()) :: {String.t(), String.t()}
  defp take_field_accessor(<<".", rest::binary>>) do
    {ident, tail} = take_while(rest, &lower_identifier_char?/1)
    {"." <> ident, tail}
  end

  @spec take_number_literal(term()) :: {String.t(), String.t()}
  defp take_number_literal(<<"0x", rest::binary>>) do
    {hex, tail} = take_while(rest, &hex_digit?/1)

    if hex == "" do
      {"0", "x" <> rest}
    else
      {"0x" <> hex, tail}
    end
  end

  defp take_number_literal(<<"0X", rest::binary>>) do
    {hex, tail} = take_while(rest, &hex_digit?/1)

    if hex == "" do
      {"0", "X" <> rest}
    else
      {"0X" <> hex, tail}
    end
  end

  defp take_number_literal(input) do
    {int_part, rest} = take_while(input, &digit?/1)

    {with_fraction, rest} =
      case rest do
        <<".", next::utf8, tail::binary>> when next in ?0..?9 ->
          {frac_digits, tail_rest} = take_while(<<next::utf8, tail::binary>>, &digit?/1)
          {int_part <> "." <> frac_digits, tail_rest}

        _ ->
          {int_part, rest}
      end

    case rest do
      <<e, sign_or_digit::utf8, _::binary>> = exp_rest when e in [?e, ?E] ->
        cond do
          sign_or_digit in [?+, ?-] ->
            case exp_rest do
              <<_e::utf8, sign::utf8, d::utf8, remaining::binary>> when d in ?0..?9 ->
                {exp_digits, tail} = take_while(<<d::utf8, remaining::binary>>, &digit?/1)
                {with_fraction <> <<e::utf8, sign::utf8>> <> exp_digits, tail}

              _ ->
                {with_fraction, rest}
            end

          digit?(sign_or_digit) ->
            <<_e::utf8, first_digit::utf8, remaining::binary>> = exp_rest
            {exp_digits, tail} = take_while(<<first_digit::utf8, remaining::binary>>, &digit?/1)
            {with_fraction <> <<e::utf8>> <> exp_digits, tail}

          true ->
            {with_fraction, rest}
        end

      _ ->
        {with_fraction, rest}
    end
  end

  defp take_while(<<char::utf8, rest::binary>>, predicate, acc) do
    if predicate.(char) do
      take_while(rest, predicate, acc <> <<char::utf8>>)
    else
      {acc, <<char::utf8, rest::binary>>}
    end
  end

  defp take_while("", _predicate, acc), do: {acc, ""}

  @spec take_backtick_operator(term(), term()) :: {:ok, String.t(), String.t()} | :error
  defp take_backtick_operator(<<"`", rest::binary>>, acc) do
    if valid_backtick_operator_inner?(acc), do: {:ok, acc, rest}, else: :error
  end

  defp take_backtick_operator(<<char::utf8, rest::binary>>, acc) do
    if backtick_operator_char?(char) do
      take_backtick_operator(rest, acc <> <<char::utf8>>)
    else
      :error
    end
  end

  defp take_backtick_operator("", _acc), do: :error

  @spec take_parenthesized_field_accessor(term(), term()) ::
          {:ok, String.t(), String.t()} | :error
  defp take_parenthesized_field_accessor(<<")", rest::binary>>, acc) do
    if acc != "", do: {:ok, acc, rest}, else: :error
  end

  defp take_parenthesized_field_accessor(<<char::utf8, rest::binary>>, acc) do
    if lower_identifier_char?(char) do
      take_parenthesized_field_accessor(rest, acc <> <<char::utf8>>)
    else
      :error
    end
  end

  defp take_parenthesized_field_accessor("", _acc), do: :error

  @spec take_parenthesized_field_accessor_with_ws(term()) ::
          {:ok, String.t(), String.t()} | :error
  defp take_parenthesized_field_accessor_with_ws(rest) when is_binary(rest) do
    {leading_ws, after_leading_ws} = take_while(rest, &ws_char?/1)

    case after_leading_ws do
      <<".", first::utf8, tail::binary>> when (first >= ?a and first <= ?z) or first == ?_ ->
        {ident, after_ident} =
          take_while(<<first::utf8, tail::binary>>, &lower_identifier_char?/1)

        {trailing_ws, after_trailing_ws} = take_while(after_ident, &ws_char?/1)

        case after_trailing_ws do
          <<")", remaining::binary>> ->
            {:ok, leading_ws <> "." <> ident <> trailing_ws <> ")", remaining}

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  @spec take_operator_section_with_ws(term()) :: {:ok, String.t(), String.t()} | :error
  defp take_operator_section_with_ws(rest) when is_binary(rest) do
    {leading_ws, after_leading_ws} = take_while(rest, &ws_char?/1)
    {op, after_op} = take_while(after_leading_ws, &operator_symbol_char?/1)

    if op == "" do
      :error
    else
      {trailing_ws, after_trailing_ws} = take_while(after_op, &ws_char?/1)

      case after_trailing_ws do
        <<")", tail::binary>> ->
          {:ok, leading_ws <> op <> trailing_ws <> ")", tail}

        _ ->
          :error
      end
    end
  end

  @spec ws_char?(term()) :: boolean()
  defp ws_char?(char), do: char in [?\s, ?\t, ?\n, ?\r]

  @spec direct_field_accessor_allowed?(term(), term(), term()) :: boolean()
  defp direct_field_accessor_allowed?(tokens, line, column) when is_list(tokens) do
    case adjacent_left_token(tokens, line, column) do
      nil ->
        case previous_non_trivia_on_line(tokens, line, column) do
          %{class: klass} when klass in ["number", "string"] -> false
          %{class: "type_identifier"} = token -> qualified_value_identifier_token?(token)
          _ -> true
        end

      token ->
        dot_access_left_token?(token) or compact_pipeline_operator_token?(token)
    end
  end

  @spec adjacent_left_token(term(), term(), term()) :: token() | nil
  defp adjacent_left_token(tokens, line, column) when is_list(tokens) do
    Enum.find(tokens, fn t ->
      not trivia_token?(t) and
        t.line == line and
        is_integer(t.column) and
        is_integer(t.length) and
        t.column + t.length == column
    end)
  end

  @spec previous_non_trivia_on_line(term(), term(), term()) :: token() | nil
  defp previous_non_trivia_on_line(tokens, line, column) when is_list(tokens) do
    Enum.find(tokens, fn t ->
      not trivia_token?(t) and
        t.line == line and
        is_integer(t.column) and
        t.column < column
    end)
  end

  @spec compact_pipeline_operator_token?(term()) :: boolean()
  defp compact_pipeline_operator_token?(%{class: "operator", text: text})
       when text in ["|>", "<|"],
       do: true

  defp compact_pipeline_operator_token?(_), do: false

  @spec split_compact_field_accessor_operator(term(), term(), term(), term(), term()) ::
          {:split, String.t(), String.t()} | :no_split
  defp split_compact_field_accessor_operator(op, tail, tokens, line, column)
       when is_binary(op) and is_binary(tail) do
    cond do
      op in ["|>.", "<|."] and starts_lower_identifier?(tail) and
          compact_accessor_left_context?(tokens, line, column) ->
        prefix = String.slice(op, 0, byte_size(op) - 1)
        {:split, prefix, "." <> tail}

      true ->
        :no_split
    end
  end

  @spec starts_lower_identifier?(term()) :: boolean()
  defp starts_lower_identifier?(<<char::utf8, _::binary>>) do
    (char >= ?a and char <= ?z) or char == ?_
  end

  defp starts_lower_identifier?(_), do: false

  @spec compact_accessor_left_context?(term(), term(), term()) :: boolean()
  defp compact_accessor_left_context?(tokens, line, column) when is_list(tokens) do
    case adjacent_left_token(tokens, line, column) do
      nil -> false
      token -> compact_accessor_left_token_allowed?(token)
    end
  end

  @spec compact_accessor_left_token_allowed?(term()) :: boolean()
  defp compact_accessor_left_token_allowed?(token) do
    dot_access_left_token?(token) or qualified_value_identifier_token?(token)
  end

  @spec take_operator_section(term(), term()) :: {:ok, String.t(), String.t()} | :error
  defp take_operator_section(<<")", rest::binary>>, acc) do
    if acc != "", do: {:ok, acc, rest}, else: :error
  end

  defp take_operator_section(<<char::utf8, rest::binary>>, acc) do
    if operator_symbol_char?(char) do
      take_operator_section(rest, acc <> <<char::utf8>>)
    else
      :error
    end
  end

  defp take_operator_section("", _acc), do: :error

  @spec lower_identifier_char?(term()) :: boolean()
  defp lower_identifier_char?(char) do
    (char >= ?a and char <= ?z) or
      (char >= ?A and char <= ?Z) or
      (char >= ?0 and char <= ?9) or
      char in [?_, ?']
  end

  @spec digit?(term()) :: boolean()
  defp digit?(char), do: char in ?0..?9

  @spec hex_digit?(term()) :: boolean()
  defp hex_digit?(char) do
    digit?(char) or char in ?a..?f or char in ?A..?F
  end

  @spec upper_identifier_char?(term()) :: boolean()
  defp upper_identifier_char?(char) do
    (char >= ?a and char <= ?z) or
      (char >= ?A and char <= ?Z) or
      (char >= ?0 and char <= ?9) or
      char in [?_, ?., ?']
  end

  @spec backtick_operator_char?(term()) :: boolean()
  defp backtick_operator_char?(char) do
    (char >= ?a and char <= ?z) or
      (char >= ?A and char <= ?Z) or
      (char >= ?0 and char <= ?9) or
      char in [?_, ?', ?.]
  end

  @spec valid_backtick_operator_inner?(term()) :: boolean()
  defp valid_backtick_operator_inner?(inner) when is_binary(inner) do
    Regex.match?(~r/^[a-z][A-Za-z0-9_'.]*$/, inner)
  end

  @spec operator_symbol_char?(term()) :: boolean()
  defp operator_symbol_char?(char) do
    char in [?!, ?#, ?$, ?%, ?&, ?*, ?+, ?,, ?-, ?., ?/, ?:, ?<, ?=, ?>, ?@, ?^, ?|, ?~]
  end

  @spec operator_run_char?(term()) :: boolean()
  defp operator_run_char?(char) do
    operator_symbol_char?(char)
  end

  @spec advance(term(), term(), term()) :: {integer(), integer()}
  defp advance(text, line, column) do
    lines = String.split(text, "\n")

    case lines do
      [single] ->
        {line, column + String.length(single)}

      _ ->
        {line + length(lines) - 1, String.length(List.last(lines)) + 1}
    end
  end

  @spec delimiter_diagnostics(term()) :: [diagnostic()]
  defp delimiter_diagnostics(tokens) do
    {stack, diagnostics} =
      Enum.reduce(tokens, {[], []}, fn token, {stack, diagnostics} ->
        case token.text do
          "(" ->
            {[{")", token} | stack], diagnostics}

          "[" ->
            {[{"]", token} | stack], diagnostics}

          "{" ->
            {[{"}", token} | stack], diagnostics}

          closing when closing in [")", "]", "}"] ->
            reduce_closing(closing, token, stack, diagnostics)

          _ ->
            {stack, diagnostics}
        end
      end)

    unclosed =
      stack
      |> Enum.map(fn {expected, token} ->
        title_id = unclosed_delimiter_title(expected, token, tokens)
        TokenizerParserMapper.unclosed_delimiter(expected, token, title_id)
      end)

    diagnostics ++ unclosed
  end

  @spec field_label_diagnostics(term()) :: [diagnostic()]
  defp field_label_diagnostics(tokens) do
    tokens
    |> record_field_label_tokens()
    |> Enum.filter(&(&1.class == "type_identifier"))
    |> Enum.map(&TokenizerParserMapper.unexpected_capital_field/1)
  end

  @spec record_field_label_tokens(term()) :: [token()]
  defp record_field_label_tokens(tokens) when is_list(tokens) do
    do_record_field_label_tokens(tokens, 0, [])
  end

  @spec do_record_field_label_tokens(term(), term(), term()) :: [token()]
  defp do_record_field_label_tokens([], _brace_depth, acc), do: Enum.reverse(acc)

  defp do_record_field_label_tokens([token | rest], brace_depth, acc) do
    case token.text do
      "{" ->
        do_record_field_label_tokens(rest, brace_depth + 1, acc)

      "}" ->
        do_record_field_label_tokens(rest, max(brace_depth - 1, 0), acc)

      _ ->
        acc =
          if brace_depth > 0 and token.class in ["identifier", "type_identifier"] and
               next_non_trivia_is_colon?(rest) do
            [token | acc]
          else
            acc
          end

        do_record_field_label_tokens(rest, brace_depth, acc)
    end
  end

  @spec reduce_closing(term(), term(), term(), term()) :: {list(), [diagnostic()]}
  defp reduce_closing(closing, _token, [{closing, _opening_token} | rest], diagnostics) do
    {rest, diagnostics}
  end

  defp reduce_closing(closing, token, stack, diagnostics) do
    diagnostic = TokenizerParserMapper.unexpected_closing_delimiter(closing, token)

    {stack, diagnostics ++ [diagnostic]}
  end

  @spec unclosed_delimiter_title(term(), term(), term()) :: atom()
  defp unclosed_delimiter_title("]", _token, _tokens), do: :unfinished_list
  defp unclosed_delimiter_title("}", _token, _tokens), do: :unfinished_record

  defp unclosed_delimiter_title(")", token, tokens) do
    if tuple_opening?(token, tokens) do
      :unfinished_tuple
    else
      :unfinished_parentheses
    end
  end

  defp unclosed_delimiter_title(_expected, _token, _tokens), do: :unclosed_delimiter

  @spec tuple_opening?(term(), term()) :: boolean()
  defp tuple_opening?(opening, tokens) when is_map(opening) and is_list(tokens) do
    open_idx =
      Enum.find_index(tokens, fn token ->
        token.text == opening.text and token.line == opening.line and
          token.column == opening.column
      end)

    case open_idx do
      nil ->
        false

      idx ->
        tokens
        |> Enum.drop(idx + 1)
        |> Enum.reduce_while({1, false}, fn token, {depth, saw_comma} ->
          cond do
            token.text == "(" ->
              {:cont, {depth + 1, saw_comma}}

            token.text == ")" and depth == 1 ->
              {:halt, {0, saw_comma}}

            token.text == ")" ->
              {:cont, {depth - 1, saw_comma}}

            depth == 1 and token.text == "," ->
              {:cont, {depth, true}}

            true ->
              {:cont, {depth, saw_comma}}
          end
        end)
        |> elem(1)
    end
  end

  @spec compiler_lex(term()) :: term()
  defp compiler_lex(source) do
    with :ok <- ensure_elm_ex_modules_loaded(),
         {:ok, lex_tokens, diagnostics, parser_payload} <- run_elm_ex_lex(source) do
      {:ok,
       %{
         tokens: Enum.map(lex_tokens, &encode_elmc_token/1),
         diagnostics: diagnostics,
         parser_payload: parser_payload
       }}
    else
      {:error, %{line: _line, reason: _reason, diagnostics: _diagnostics} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end

  @spec run_elm_ex_lex(term()) :: term()
  defp run_elm_ex_lex(source) do
    lexer_mod = :elm_ex_elm_lexer
    module_parser = module_parser_result(source)
    module_parser_diags = module_parser.diagnostics
    declaration_parser_diags = declaration_parser_diagnostics(source)
    expression_parser_diags = expression_parser_diagnostics(source)
    diagnostics = module_parser_diags ++ declaration_parser_diags ++ expression_parser_diags
    parser_payload = module_parser.payload

    case apply(lexer_mod, :string, [String.to_charlist(source)]) do
      {:ok, tokens, _line} ->
        {:ok, tokens, diagnostics, parser_payload}

      {:error, reason, line} ->
        {:error,
         %{
           line: line,
           reason: inspect(reason),
           diagnostics: diagnostics,
           parser_payload: parser_payload
         }}

      {:error, reason} ->
        {:error,
         %{
           line: nil,
           reason: inspect(reason),
           diagnostics: diagnostics,
           parser_payload: parser_payload
         }}
    end
  end

  @spec module_parser_result(String.t()) :: %{
          diagnostics: [diagnostic()],
          payload: parser_payload() | nil
        }
  defp module_parser_result(source) do
    lexer_mod = :elm_ex_elm_lexer
    parser_mod = :elm_ex_elm_parser
    metadata_source = ElmEx.Frontend.GeneratedParser.normalize_source_for_metadata(source)
    source_hash = :erlang.phash2(source)

    case apply(lexer_mod, :string, [String.to_charlist(metadata_source)]) do
      {:ok, module_tokens, _line} ->
        case apply(parser_mod, :parse, [
               ElmEx.Frontend.GeneratedParser.metadata_subset_tokens(module_tokens)
             ]) do
          {:ok, metadata_values} ->
            metadata =
              HeaderMetadata.from_values_and_tokens(source, metadata_values, module_tokens)

            %{
              diagnostics: [],
              payload: %{
                diagnostics: [],
                metadata: metadata,
                source_hash: source_hash,
                fallback?: false
              }
            }

          {:error, reason} ->
            parser_line = parser_error_line(reason)

            %{
              diagnostics: [
                parser_diagnostic("module_parser", parser_line, %{
                  message: inspect(reason),
                  elm_title: classify_module_parser_title(source, parser_line, inspect(reason))
                })
              ],
              payload: nil
            }
        end

      {:error, reason, line} ->
        %{
          diagnostics: [
            parser_diagnostic("module_lexer", line, %{
              message: inspect(reason),
              elm_title: :unexpected_character
            })
          ],
          payload: nil
        }

      {:error, reason} ->
        %{
          diagnostics: [
            parser_diagnostic("module_lexer", nil, %{
              message: inspect(reason),
              elm_title: :unexpected_character
            })
          ],
          payload: nil
        }
    end
  end

  @spec maybe_formatter_parser_payload(term()) :: parser_payload() | nil
  defp maybe_formatter_parser_payload(source) when is_binary(source) do
    with :ok <- ensure_elm_ex_modules_loaded() do
      module_parser_result(source).payload
    else
      _ -> nil
    end
  end

  @spec parser_error_line(term()) :: integer()
  defp parser_error_line(reason) do
    case reason do
      {line, _module, _term} when is_integer(line) -> line
      {line, _term} when is_integer(line) -> line
      _ -> 1
    end
  end

  @spec classify_module_parser_title(term(), term(), term()) :: atom()
  defp classify_module_parser_title(source, line, reason_text)
       when is_binary(source) and is_integer(line) and is_binary(reason_text) do
    line_text =
      source
      |> String.split("\n", trim: false)
      |> Enum.at(max(line - 1, 0), "")
      |> String.trim()

    cond do
      String.starts_with?(line_text, "module") and not String.contains?(line_text, " exposing ") ->
        :unfinished_module_declaration

      String.starts_with?(line_text, "module") and String.contains?(line_text, " exposing") and
          not String.contains?(line_text, "(") ->
        :unfinished_exposing

      String.starts_with?(line_text, "import ") and
          not Regex.match?(~r/^import\s+[A-Z]/, line_text) ->
        :expecting_import_name

      String.starts_with?(line_text, "import ") and String.contains?(line_text, " as ") and
          not Regex.match?(~r/\sas\s+[A-Z]/, line_text) ->
        :expecting_import_alias

      String.starts_with?(line_text, "import ") and String.contains?(line_text, " exposing") and
          not String.contains?(line_text, "(") ->
        :unfinished_exposing

      String.starts_with?(line_text, "import ") and String.contains?(line_text, " exposing") ->
        :problem_in_exposing

      String.contains?(reason_text, "syntax error before:") ->
        :bad_module_declaration

      true ->
        :syntax_problem
    end
  end

  @spec declaration_parser_diagnostics(term()) :: [diagnostic()]
  defp declaration_parser_diagnostics(source) do
    {diags, _state} =
      source
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.reduce({[], %{in_type_decl: false}}, fn {line_text, line_no}, {acc, state} ->
        trimmed = String.trim(line_text)

        cond do
          trimmed == "" or String.starts_with?(trimmed, "--") ->
            {acc, state}

          String.starts_with?(trimmed, "module ") ->
            {acc, %{state | in_type_decl: false}}

          String.starts_with?(trimmed, "import ") ->
            {acc, %{state | in_type_decl: false}}

          String.starts_with?(trimmed, "port module ") ->
            {acc, %{state | in_type_decl: false}}

          String.starts_with?(trimmed, "type ") ->
            title =
              if String.starts_with?(trimmed, "type alias "),
                do: :problem_in_type_alias,
                else: :problem_in_custom_type

            parse_diags =
              if type_declaration_header_open?(trimmed) do
                []
              else
                parse_decl_line(trimmed, line_no, title)
              end

            line_diags =
              parse_diags ++
                type_declaration_header_diagnostics(trimmed, line_no)

            {line_diags ++ acc, %{state | in_type_decl: true}}

          state.in_type_decl and Regex.match?(~r/^[=|]\s*/, trimmed) ->
            line_diags =
              parse_decl_line(trimmed, line_no, :problem_in_custom_type) ++
                type_constructor_line_diagnostics(trimmed, line_no)

            {line_diags ++ acc, state}

          String.starts_with?(trimmed, "port ") ->
            line_diags =
              parse_decl_line(trimmed, line_no, :port_problem) ++
                port_declaration_diagnostics(trimmed, line_no)

            {line_diags ++ acc, %{state | in_type_decl: false}}

          Regex.match?(~r/^[a-z][A-Za-z0-9_']*(\s+[a-z][A-Za-z0-9_']*)*\s*=\s*.+$/, trimmed) ->
            [lhs | _rest] = String.split(trimmed, "=", parts: 2)
            header = String.trim(lhs) <> " ="
            line_diags = parse_decl_line(header, line_no, :problem_in_definition)
            {line_diags ++ acc, %{state | in_type_decl: false}}

          true ->
            {acc, %{state | in_type_decl: false}}
        end
      end)

    Enum.reverse(diags)
  end

  @spec parse_decl_line(term(), term(), term()) :: [map()]
  defp parse_decl_line(text, line_no, elm_title) when is_binary(text) and is_integer(line_no) do
    decl_lexer_mod = :elm_ex_decl_lexer
    decl_parser_mod = :elm_ex_decl_parser

    case apply(decl_lexer_mod, :string, [String.to_charlist(text)]) do
      {:ok, decl_tokens, _} ->
        case apply(decl_parser_mod, :parse, [decl_tokens]) do
          {:ok, _decl} ->
            []

          {:error, reason} ->
            reason_text = inspect(reason)

            [
              parser_diagnostic("decl_parser", line_no, %{
                message: reason_text,
                elm_title: infer_decl_title(text, elm_title, reason_text)
              })
            ]
        end

      {:error, reason, _line} ->
        [
          parser_diagnostic("decl_lexer", line_no, %{
            message: inspect(reason),
            elm_title: :unexpected_character
          })
        ]

      {:error, reason} ->
        [
          parser_diagnostic("decl_lexer", line_no, %{
            message: inspect(reason),
            elm_title: :unexpected_character
          })
        ]
    end
  end

  @spec infer_decl_title(term(), term(), term()) :: atom()
  defp infer_decl_title(text, default_title, reason_text)
       when is_binary(text) and is_atom(default_title) and is_binary(reason_text) do
    trimmed = String.trim(text)

    cond do
      String.starts_with?(trimmed, "type alias") and
          String.contains?(reason_text, "syntax error before:") ->
        :expecting_type_alias_name

      String.starts_with?(trimmed, "type ") and
          String.contains?(reason_text, "syntax error before:") ->
        :expecting_type_name

      String.starts_with?(trimmed, "port ") and
          String.contains?(reason_text, "syntax error before:") ->
        :port_problem

      true ->
        default_title
    end
  end

  @spec type_declaration_header_open?(term()) :: boolean()
  defp type_declaration_header_open?(trimmed) when is_binary(trimmed) do
    if String.contains?(trimmed, "=") do
      {_lhs, rhs} = split_once_text(trimmed, "=")
      String.trim(rhs) == ""
    else
      false
    end
  end

  @spec expression_parser_diagnostics(term()) :: [diagnostic()]
  defp expression_parser_diagnostics(source) when is_binary(source) do
    expr_lexer_mod = :elm_ex_expr_lexer
    expr_parser_mod = :elm_ex_expr_parser
    indexed_lines = source |> String.split("\n") |> Enum.with_index(1)

    indexed_lines
    |> Enum.flat_map(fn {line_text, line_no} ->
      trimmed = String.trim(line_text)
      line_indent = leading_indent_width(line_text)

      cond do
        trimmed == "" or String.starts_with?(trimmed, "--") ->
          []

        String.starts_with?(trimmed, "module ") or String.starts_with?(trimmed, "import ") or
          String.starts_with?(trimmed, "type ") or String.starts_with?(trimmed, "port ") ->
          []

        assignment_header_line?(trimmed) ->
          {_lhs, rhs} = split_once_text(trimmed, "=")
          rhs_trimmed = String.trim(rhs)

          if rhs_trimmed == "" do
            if multiline_assignment_continues?(indexed_lines, line_no, line_indent) do
              []
            else
              [
                parser_diagnostic("expr_parser", line_no, %{
                  message: "Missing expression after =",
                  elm_title: :missing_expression
                })
              ]
            end
          else
            parse_expression_snippet(rhs_trimmed, line_no, expr_lexer_mod, expr_parser_mod)
          end

        String.starts_with?(trimmed, "case ") and String.ends_with?(trimmed, " of") ->
          []

        trimmed == "let" ->
          []

        String.starts_with?(trimmed, "let ") and not String.contains?(trimmed, " in ") ->
          []

        inline_if_expression?(trimmed) or String.starts_with?(trimmed, "case ") ->
          parse_expression_snippet(trimmed, line_no, expr_lexer_mod, expr_parser_mod)

        true ->
          []
      end
    end)
  end

  @spec assignment_header_line?(term()) :: boolean()
  defp assignment_header_line?(trimmed) when is_binary(trimmed) do
    Regex.match?(~r/^[a-z][A-Za-z0-9_']*(\s+[a-z][A-Za-z0-9_']*)*\s*=/, trimmed)
  end

  @spec inline_if_expression?(String.t()) :: boolean()
  defp inline_if_expression?(trimmed) when is_binary(trimmed) do
    String.starts_with?(trimmed, "if ") and String.contains?(trimmed, " then ") and
      String.contains?(trimmed, " else ")
  end

  @spec multiline_assignment_continues?(term(), term(), term()) :: boolean()
  defp multiline_assignment_continues?(indexed_lines, line_no, line_indent)
       when is_list(indexed_lines) and is_integer(line_no) and is_integer(line_indent) do
    indexed_lines
    |> Enum.drop(line_no)
    |> Enum.find_value(false, fn {line_text, _next_line_no} ->
      next_trimmed = String.trim(line_text)

      cond do
        next_trimmed == "" or String.starts_with?(next_trimmed, "--") ->
          nil

        true ->
          next_indent = leading_indent_width(line_text)
          next_indent > line_indent
      end
    end)
  end

  @spec leading_indent_width(term()) :: non_neg_integer()
  defp leading_indent_width(line_text) when is_binary(line_text) do
    line_text
    |> String.graphemes()
    |> Enum.take_while(&(&1 == " " or &1 == "\t"))
    |> length()
  end

  @spec parse_expression_snippet(term(), term(), term(), term()) :: [map()]
  defp parse_expression_snippet(snippet, line_no, expr_lexer_mod, expr_parser_mod)
       when is_binary(snippet) and is_integer(line_no) do
    case apply(expr_lexer_mod, :string, [String.to_charlist(snippet)]) do
      {:ok, expr_tokens, _} ->
        case apply(expr_parser_mod, :parse, [expr_tokens]) do
          {:ok, _expr} ->
            []

          {:error, reason} ->
            [
              parser_diagnostic("expr_parser", line_no, %{
                message: inspect(reason),
                elm_title: infer_expression_title(snippet, inspect(reason))
              })
            ]
        end

      {:error, reason, _line} ->
        [
          parser_diagnostic("expr_lexer", line_no, %{
            message: inspect(reason),
            elm_title: :unexpected_character
          })
        ]

      {:error, reason} ->
        [
          parser_diagnostic("expr_lexer", line_no, %{
            message: inspect(reason),
            elm_title: :unexpected_character
          })
        ]
    end
  end

  @spec infer_expression_title(term(), term()) :: atom()
  defp infer_expression_title(snippet, reason) when is_binary(snippet) and is_binary(reason) do
    cond do
      String.starts_with?(snippet, "let ") and not String.contains?(snippet, " in ") ->
        :unfinished_let

      String.starts_with?(snippet, "if ") and
          (not String.contains?(snippet, " then ") or not String.contains?(snippet, " else ")) ->
        :unfinished_if

      String.starts_with?(snippet, "case ") and not String.contains?(snippet, " of") ->
        :unfinished_case

      String.ends_with?(snippet, "->") ->
        :missing_expression

      String.contains?(reason, "'->'") ->
        :missing_arrow

      String.contains?(reason, "syntax error before:") ->
        :missing_expression

      true ->
        :syntax_problem
    end
  end

  @spec type_declaration_header_diagnostics(term(), term()) :: [map()]
  defp type_declaration_header_diagnostics(trimmed, line_no)
       when is_binary(trimmed) and is_integer(line_no) do
    header =
      trimmed
      |> strip_inline_comment()
      |> String.trim()

    cond do
      String.starts_with?(header, "type alias ") ->
        validate_type_header_shape(header, "type alias ", line_no)

      String.starts_with?(header, "type ") ->
        validate_type_header_shape(header, "type ", line_no)

      true ->
        []
    end
  end

  @spec type_constructor_line_diagnostics(term(), term()) :: [map()]
  defp type_constructor_line_diagnostics(trimmed, line_no)
       when is_binary(trimmed) and is_integer(line_no) do
    constructor_head =
      trimmed
      |> String.trim_leading("=")
      |> String.trim_leading("|")
      |> String.trim()
      |> String.split(~r/\s+/, trim: true)
      |> List.first()

    cond do
      not is_binary(constructor_head) or constructor_head == "" ->
        [parser_diagnostic("decl_parser", line_no, "Invalid custom type constructor")]

      upper_identifier?(constructor_head) ->
        []

      true ->
        [
          parser_diagnostic(
            "decl_parser",
            line_no,
            "Invalid custom type constructor '#{constructor_head}'"
          )
        ]
    end
  end

  @spec port_declaration_diagnostics(term(), term()) :: [map()]
  defp port_declaration_diagnostics(trimmed, line_no)
       when is_binary(trimmed) and is_integer(line_no) do
    valid? =
      Regex.match?(~r/^port\s+[a-z][A-Za-z0-9_']*\s*:/, trimmed) or
        Regex.match?(~r/^port\s+module\s+[A-Z][A-Za-z0-9_']*\s+exposing\b/, trimmed)

    if valid? do
      []
    else
      [parser_diagnostic("decl_parser", line_no, "Invalid port declaration header")]
    end
  end

  @spec validate_type_header_shape(term(), term(), term()) :: [map()]
  defp validate_type_header_shape(header, prefix, line_no)
       when is_binary(header) and is_binary(prefix) and is_integer(line_no) do
    remainder = String.replace_prefix(header, prefix, "")
    {head_part, _rhs_part} = split_once_text(remainder, "=")

    parts =
      head_part
      |> String.trim()
      |> String.split(~r/\s+/, trim: true)

    case parts do
      [type_name | vars] ->
        cond do
          not upper_identifier?(type_name) ->
            [parser_diagnostic("decl_parser", line_no, "Invalid type declaration header")]

          invalid = Enum.find(vars, &(not lower_identifier?(&1))) ->
            [parser_diagnostic("decl_parser", line_no, "Invalid type variable '#{invalid}'")]

          true ->
            []
        end

      _ ->
        [parser_diagnostic("decl_parser", line_no, "Invalid type declaration header")]
    end
  end

  @spec parser_diagnostic(term(), term(), term()) :: map()
  defp parser_diagnostic(source_name, line, reason) do
    reason_map =
      case reason do
        %{} = data ->
          data

        _ ->
          %{message: normalize_elmc_value(reason)}
      end

    %{
      source: source_name,
      line: line,
      message: normalize_elmc_value(reason_map[:message] || "Parser reported an issue."),
      elm_title: reason_map[:elm_title],
      detail: reason_map[:detail]
    }
  end

  @spec split_once_text(term(), term()) :: {String.t(), String.t()}
  defp split_once_text(value, delimiter) when is_binary(value) and is_binary(delimiter) do
    case String.split(value, delimiter, parts: 2) do
      [before, remainder] -> {before, remainder}
      [before] -> {before, ""}
      _ -> {"", ""}
    end
  end

  @spec strip_inline_comment(term()) :: String.t()
  defp strip_inline_comment(value) when is_binary(value) do
    case String.split(value, "--", parts: 2) do
      [before, _after] -> before
      _ -> value
    end
  end

  @spec upper_identifier?(term()) :: boolean()
  defp upper_identifier?(value) when is_binary(value) do
    Regex.match?(~r/^[A-Z][A-Za-z0-9_']*$/, value)
  end

  @spec lower_identifier?(term()) :: boolean()
  defp lower_identifier?(value) when is_binary(value) do
    Regex.match?(~r/^[a-z][A-Za-z0-9_']*$/, value)
  end

  @spec encode_elmc_token(term()) :: map()
  defp encode_elmc_token({type, line, value}) do
    text = normalize_elmc_value(value)
    %{"type" => Atom.to_string(type), "line" => line, "value" => text, "text" => text}
  end

  defp encode_elmc_token({type, line}) do
    %{"type" => Atom.to_string(type), "line" => line, "text" => token_text_from_type(type)}
  end

  defp encode_elmc_token(other) do
    %{"type" => "unknown", "line" => nil, "value" => inspect(other)}
  end

  @spec normalize_elmc_value(term()) :: String.t()
  defp normalize_elmc_value(value) do
    cond do
      is_binary(value) -> value
      is_list(value) -> List.to_string(value)
      is_atom(value) -> Atom.to_string(value)
      is_number(value) -> to_string(value)
      true -> inspect(value)
    end
  end

  @spec ensure_elm_ex_modules_loaded() :: :ok | {:error, term()}
  defp ensure_elm_ex_modules_loaded do
    ebin_path = Path.join([elm_ex_root(), "_build", "dev", "lib", "elm_ex", "ebin"])

    if File.dir?(ebin_path) do
      Code.append_path(String.to_charlist(ebin_path))
    end

    required_modules = [
      :elm_ex_elm_lexer,
      :elm_ex_elm_parser,
      :elm_ex_decl_lexer,
      :elm_ex_decl_parser,
      :elm_ex_expr_lexer,
      :elm_ex_expr_parser
    ]

    parser_module = ElmEx.Frontend.GeneratedParser

    missing =
      Enum.find(required_modules, fn mod ->
        match?({:error, _}, Code.ensure_loaded(mod))
      end)

    cond do
      is_atom(missing) and not is_nil(missing) ->
        {:error,
         "elm_ex parser modules are not loaded (missing #{inspect(missing)}). Build elm_ex once to provide BEAM artifacts."}

      true ->
        case Code.ensure_loaded(parser_module) do
          {:module, ^parser_module} ->
            helpers_loaded? =
              function_exported?(parser_module, :normalize_source_for_metadata, 1) and
                function_exported?(parser_module, :metadata_subset_tokens, 1)

            if helpers_loaded? do
              :ok
            else
              {:error,
               "Loaded ElmEx.Frontend.GeneratedParser is missing metadata helpers. Recompile `elm_ex` and restart IDE (`mix deps.compile elm_ex --force`)."}
            end

          {:error, _reason} ->
            {:error,
             "ElmEx.Frontend.GeneratedParser is not loaded. Recompile `elm_ex` and restart IDE (`mix deps.compile elm_ex --force`)."}
        end
    end
  end

  @spec apply_elmc_classes(term(), term()) :: [token()]
  defp apply_elmc_classes(tokens, lex_tokens) do
    lex_by_line = Enum.group_by(lex_tokens, & &1["line"])

    {merged, _state} =
      Enum.map_reduce(tokens, lex_by_line, fn token, state ->
        if trivia_token?(token) do
          {token, state}
        else
          {klass, next_state} = next_matching_lex_class(state, token.line, token.text)

          case klass do
            nil ->
              {token, next_state}

            _ ->
              merged_class =
                cond do
                  token.class == "keyword" and klass == "identifier" -> token.class
                  token.class == "number" and klass == "identifier" -> token.class
                  true -> klass
                end

              {%{token | class: merged_class}, next_state}
          end
        end
      end)

    merged
  end

  @spec mark_record_field_identifiers(term()) :: [token()]
  defp mark_record_field_identifiers(tokens) when is_list(tokens) do
    do_mark_record_field_identifiers(tokens, 0, [])
  end

  @spec do_mark_record_field_identifiers(term(), term(), term()) :: [token()]
  defp do_mark_record_field_identifiers([], _brace_depth, acc), do: Enum.reverse(acc)

  defp do_mark_record_field_identifiers([token | rest], brace_depth, acc) do
    case token.text do
      "{" ->
        do_mark_record_field_identifiers(rest, brace_depth + 1, [token | acc])

      "}" ->
        do_mark_record_field_identifiers(rest, max(brace_depth - 1, 0), [token | acc])

      _ ->
        marked =
          if brace_depth > 0 and token.class == "identifier" and next_non_trivia_is_colon?(rest) do
            %{token | class: "field_identifier"}
          else
            token
          end

        do_mark_record_field_identifiers(rest, brace_depth, [marked | acc])
    end
  end

  @spec next_non_trivia_is_colon?(term()) :: boolean()
  defp next_non_trivia_is_colon?([]), do: false

  defp next_non_trivia_is_colon?([token | rest]) do
    cond do
      trivia_token?(token) ->
        next_non_trivia_is_colon?(rest)

      true ->
        token.text == ":"
    end
  end

  @spec next_non_trivia_is_pipe?(term()) :: boolean()
  defp next_non_trivia_is_pipe?([]), do: false

  defp next_non_trivia_is_pipe?([token | rest]) do
    cond do
      trivia_token?(token) ->
        next_non_trivia_is_pipe?(rest)

      true ->
        token.text == "|"
    end
  end

  @spec mark_type_annotation_operators(term()) :: [token()]
  defp mark_type_annotation_operators(tokens) when is_list(tokens) do
    lines_map = Enum.group_by(tokens, & &1.line)
    sorted_lines = lines_map |> Map.keys() |> Enum.sort()

    annotation_lines =
      Enum.reduce(sorted_lines, MapSet.new(), fn line, acc ->
        line_tokens = Map.get(lines_map, line, [])

        if annotation_start_line?(line_tokens) do
          include = annotation_continuation_lines(lines_map, line, sorted_lines)
          Enum.reduce(include, acc, &MapSet.put(&2, &1))
        else
          acc
        end
      end)

    Enum.map(tokens, fn token ->
      if token.text in ["->", ":"] and MapSet.member?(annotation_lines, token.line) do
        %{token | class: "type_operator"}
      else
        token
      end
    end)
  end

  @spec mark_type_declaration_operators(term()) :: [token()]
  defp mark_type_declaration_operators(tokens) when is_list(tokens) do
    declaration_lines = type_declaration_lines(tokens)

    Enum.map(tokens, fn token ->
      if token.text in ["|", "=", "(", ")", ",", "{", "}", ":", "[", "]"] and
           MapSet.member?(declaration_lines, token.line) do
        %{token | class: "type_operator"}
      else
        token
      end
    end)
  end

  @spec mark_type_declaration_identifiers(term()) :: [token()]
  defp mark_type_declaration_identifiers(tokens) when is_list(tokens) do
    declaration_lines = type_declaration_lines(tokens)

    Enum.map(tokens, fn token ->
      if token.class == "identifier" and MapSet.member?(declaration_lines, token.line) do
        %{token | class: "type_identifier"}
      else
        token
      end
    end)
  end

  @spec type_declaration_lines(term()) :: term()
  defp type_declaration_lines(tokens) when is_list(tokens) do
    lines_map = Enum.group_by(tokens, & &1.line)
    sorted_lines = lines_map |> Map.keys() |> Enum.sort()

    Enum.reduce(sorted_lines, MapSet.new(), fn line, acc ->
      line_tokens = Map.get(lines_map, line, [])

      if type_declaration_start_line?(line_tokens) do
        include = type_declaration_continuation_lines(lines_map, line, sorted_lines)
        Enum.reduce(include, acc, &MapSet.put(&2, &1))
      else
        acc
      end
    end)
  end

  @spec mark_type_alias_field_colons(term()) :: [token()]
  defp mark_type_alias_field_colons(tokens) when is_list(tokens) do
    lines_map = Enum.group_by(tokens, & &1.line)
    sorted_lines = lines_map |> Map.keys() |> Enum.sort()

    alias_lines =
      Enum.reduce(sorted_lines, MapSet.new(), fn line, acc ->
        line_tokens = Map.get(lines_map, line, [])

        if type_alias_start_line?(line_tokens) do
          include = type_declaration_continuation_lines(lines_map, line, sorted_lines)
          Enum.reduce(include, acc, &MapSet.put(&2, &1))
        else
          acc
        end
      end)

    do_mark_type_alias_field_colons(tokens, alias_lines, 0, [])
  end

  @spec mark_type_alias_head_identifiers(term()) :: [token()]
  defp mark_type_alias_head_identifiers(tokens) when is_list(tokens) do
    lines_map = Enum.group_by(tokens, & &1.line)
    sorted_lines = lines_map |> Map.keys() |> Enum.sort()

    alias_head_tokens =
      Enum.reduce(sorted_lines, MapSet.new(), fn line, acc ->
        line_tokens = Map.get(lines_map, line, [])

        if type_alias_start_line?(line_tokens) do
          line_tokens
          |> alias_head_identifier_keys()
          |> Enum.reduce(acc, fn key, set -> MapSet.put(set, key) end)
        else
          acc
        end
      end)

    Enum.map(tokens, fn token ->
      key = token_key(token)

      if token.class == "identifier" and MapSet.member?(alias_head_tokens, key) do
        %{token | class: "type_identifier"}
      else
        token
      end
    end)
  end

  @spec mark_type_alias_record_identifiers(term()) :: [token()]
  defp mark_type_alias_record_identifiers(tokens) when is_list(tokens) do
    lines_map = Enum.group_by(tokens, & &1.line)
    sorted_lines = lines_map |> Map.keys() |> Enum.sort()

    alias_lines =
      Enum.reduce(sorted_lines, MapSet.new(), fn line, acc ->
        line_tokens = Map.get(lines_map, line, [])

        if type_alias_start_line?(line_tokens) do
          include = type_declaration_continuation_lines(lines_map, line, sorted_lines)
          Enum.reduce(include, acc, &MapSet.put(&2, &1))
        else
          acc
        end
      end)

    do_mark_type_alias_record_identifiers(tokens, alias_lines, 0, false, [])
  end

  @spec mark_type_annotation_identifiers(term()) :: [token()]
  defp mark_type_annotation_identifiers(tokens) when is_list(tokens) do
    annotation_context_by_line = annotation_context_by_line(tokens)

    Enum.map(tokens, fn token ->
      case Map.get(annotation_context_by_line, token.line) do
        min_col when is_integer(min_col) ->
          if token.class == "identifier" and token.column > min_col do
            %{token | class: "type_identifier"}
          else
            token
          end

        _ ->
          token
      end
    end)
  end

  @spec mark_type_annotation_record_extension_pipes(term()) :: [token()]
  defp mark_type_annotation_record_extension_pipes(tokens) when is_list(tokens) do
    context_by_line = annotation_context_by_line(tokens)
    do_mark_type_annotation_record_extension_pipes(tokens, context_by_line, 0, [])
  end

  @spec mark_type_alias_operators(term()) :: [token()]
  defp mark_type_alias_operators(tokens) when is_list(tokens) do
    alias_lines = type_alias_lines(tokens)

    Enum.map(tokens, fn token ->
      if token.text in ["|", "=", "(", ")", ",", "{", "}", ":", "[", "]"] and
           MapSet.member?(alias_lines, token.line) do
        %{token | class: "type_operator"}
      else
        token
      end
    end)
  end

  @spec mark_type_alias_identifiers(term()) :: [token()]
  defp mark_type_alias_identifiers(tokens) when is_list(tokens) do
    alias_lines = type_alias_lines(tokens)

    Enum.map(tokens, fn token ->
      if token.class == "identifier" and MapSet.member?(alias_lines, token.line) do
        %{token | class: "type_identifier"}
      else
        token
      end
    end)
  end

  @spec mark_type_annotation_grouping_operators(term()) :: [token()]
  defp mark_type_annotation_grouping_operators(tokens) when is_list(tokens) do
    context_by_line = annotation_context_by_line(tokens)

    Enum.map(tokens, fn token ->
      if token.text in ["(", ")", ",", "[", "]", "{", "}"] and
           annotation_context_token?(token, context_by_line) do
        %{token | class: "type_operator"}
      else
        token
      end
    end)
  end

  @spec annotation_start_line?(term()) :: boolean()
  defp annotation_start_line?(line_tokens) when is_list(line_tokens) do
    colon_col = first_token_column(line_tokens, ":")
    equals_col = first_token_column(line_tokens, "=")
    arrow_col = first_token_column(line_tokens, "->")

    is_integer(colon_col) and
      (is_nil(equals_col) or colon_col < equals_col) and
      (is_nil(arrow_col) or colon_col < arrow_col) and
      annotation_line_prefix_allows?(line_tokens)
  end

  @spec annotation_start_column(term()) :: non_neg_integer() | nil
  defp annotation_start_column(line_tokens) when is_list(line_tokens) do
    case Enum.find(line_tokens, &(&1.text == ":")) do
      %{column: column} when is_integer(column) -> column
      _ -> 0
    end
  end

  @spec annotation_continuation_lines(term(), term(), term()) :: [integer()]
  defp annotation_continuation_lines(lines_map, start_line, sorted_lines) do
    remaining =
      sorted_lines
      |> Enum.drop_while(&(&1 <= start_line))

    cont =
      Enum.reduce_while(remaining, [start_line], fn line, acc ->
        line_tokens = Map.get(lines_map, line, [])

        cond do
          line_blank_or_comment_only?(line_tokens) ->
            {:cont, acc}

          line_has_text?(line_tokens, "=") ->
            {:halt, acc}

          line_indented?(line_tokens) ->
            {:cont, [line | acc]}

          true ->
            {:halt, acc}
        end
      end)

    Enum.reverse(cont)
  end

  @spec annotation_context_by_line(term()) :: map()
  defp annotation_context_by_line(tokens) when is_list(tokens) do
    lines_map = Enum.group_by(tokens, & &1.line)
    sorted_lines = lines_map |> Map.keys() |> Enum.sort()

    Enum.reduce(sorted_lines, %{}, fn line, acc ->
      line_tokens = Map.get(lines_map, line, [])

      if annotation_start_line?(line_tokens) do
        include = annotation_continuation_lines(lines_map, line, sorted_lines)
        start_col = annotation_start_column(line_tokens)

        Enum.reduce(include, acc, fn include_line, line_acc ->
          min_col = if include_line == line, do: start_col, else: 0
          Map.put(line_acc, include_line, min_col)
        end)
      else
        acc
      end
    end)
  end

  @spec type_alias_lines(term()) :: MapSet.t(integer())
  defp type_alias_lines(tokens) when is_list(tokens) do
    lines_map = Enum.group_by(tokens, & &1.line)
    sorted_lines = lines_map |> Map.keys() |> Enum.sort()

    Enum.reduce(sorted_lines, MapSet.new(), fn line, acc ->
      line_tokens = Map.get(lines_map, line, [])

      if type_alias_start_line?(line_tokens) do
        include = type_declaration_continuation_lines(lines_map, line, sorted_lines)
        Enum.reduce(include, acc, &MapSet.put(&2, &1))
      else
        acc
      end
    end)
  end

  @spec annotation_context_token?(term(), term()) :: boolean()
  defp annotation_context_token?(token, context_by_line) do
    case Map.get(context_by_line, token.line) do
      min_col when is_integer(min_col) -> token.column > min_col
      _ -> false
    end
  end

  @spec do_mark_type_annotation_record_extension_pipes(term(), term(), term(), term()) :: [
          token()
        ]
  defp do_mark_type_annotation_record_extension_pipes([], _context_by_line, _brace_depth, acc),
    do: Enum.reverse(acc)

  defp do_mark_type_annotation_record_extension_pipes(
         [token | rest],
         context_by_line,
         brace_depth,
         acc
       ) do
    {next_depth, marked} =
      case token.text do
        "{" ->
          {brace_depth + 1, token}

        "}" ->
          {max(brace_depth - 1, 0), token}

        "|" ->
          if brace_depth > 0 and Map.has_key?(context_by_line, token.line) do
            {brace_depth, %{token | class: "type_operator"}}
          else
            {brace_depth, token}
          end

        ":" ->
          if brace_depth > 0 and Map.has_key?(context_by_line, token.line) do
            {brace_depth, %{token | class: "type_operator"}}
          else
            {brace_depth, token}
          end

        _ ->
          {brace_depth, token}
      end

    do_mark_type_annotation_record_extension_pipes(
      rest,
      context_by_line,
      next_depth,
      [marked | acc]
    )
  end

  @spec type_declaration_start_line?(term()) :: boolean()
  defp type_declaration_start_line?(line_tokens) when is_list(line_tokens) do
    non_trivia = line_non_trivia_tokens(line_tokens)

    case non_trivia do
      [%{text: "type", class: "keyword"}, %{text: "alias", class: "keyword"} | _] ->
        false

      [%{text: "type", class: "keyword"} | _] ->
        true

      _ ->
        false
    end
  end

  @spec type_alias_start_line?(term()) :: boolean()
  defp type_alias_start_line?(line_tokens) when is_list(line_tokens) do
    non_trivia = line_non_trivia_tokens(line_tokens)

    match?(
      [%{text: "type", class: "keyword"}, %{text: "alias", class: "keyword"} | _],
      non_trivia
    )
  end

  @spec type_declaration_continuation_lines(term(), term(), term()) :: [integer()]
  defp type_declaration_continuation_lines(lines_map, start_line, sorted_lines) do
    remaining =
      sorted_lines
      |> Enum.drop_while(&(&1 <= start_line))

    cont =
      Enum.reduce_while(remaining, [start_line], fn line, acc ->
        line_tokens = Map.get(lines_map, line, [])
        non_trivia = line_non_trivia_tokens(line_tokens)

        cond do
          non_trivia == [] ->
            {:cont, acc}

          line_indented?(line_tokens) ->
            {:cont, [line | acc]}

          true ->
            {:halt, acc}
        end
      end)

    Enum.reverse(cont)
  end

  @spec do_mark_type_alias_field_colons(term(), term(), term(), term()) :: [token()]
  defp do_mark_type_alias_field_colons([], _alias_lines, _brace_depth, acc), do: Enum.reverse(acc)

  defp do_mark_type_alias_field_colons([token | rest], alias_lines, brace_depth, acc) do
    {next_depth, marked} =
      case token.text do
        "{" ->
          {brace_depth + 1, token}

        "}" ->
          {max(brace_depth - 1, 0), token}

        ":" ->
          if brace_depth > 0 and MapSet.member?(alias_lines, token.line) do
            {brace_depth, %{token | class: "type_operator"}}
          else
            {brace_depth, token}
          end

        "|" ->
          if brace_depth > 0 and MapSet.member?(alias_lines, token.line) do
            {brace_depth, %{token | class: "type_operator"}}
          else
            {brace_depth, token}
          end

        _ ->
          {brace_depth, token}
      end

    do_mark_type_alias_field_colons(rest, alias_lines, next_depth, [marked | acc])
  end

  @spec do_mark_type_alias_record_identifiers(term(), term(), term(), term(), term()) :: [token()]
  defp do_mark_type_alias_record_identifiers([], _alias_lines, _brace_depth, _in_field_type, acc),
    do: Enum.reverse(acc)

  defp do_mark_type_alias_record_identifiers(
         [token | rest],
         alias_lines,
         brace_depth,
         in_field_type,
         acc
       ) do
    in_alias_line? = MapSet.member?(alias_lines, token.line)

    {next_depth, next_in_field_type} =
      if in_alias_line? do
        case token.text do
          "{" -> {brace_depth + 1, in_field_type}
          "}" -> {max(brace_depth - 1, 0), false}
          ":" when brace_depth > 0 -> {brace_depth, true}
          "," when brace_depth > 0 -> {brace_depth, false}
          _ -> {brace_depth, in_field_type}
        end
      else
        {0, false}
      end

    marked =
      if in_alias_line? and brace_depth > 0 and token.class == "identifier" do
        if in_field_type or next_non_trivia_is_pipe?(rest) do
          %{token | class: "type_identifier"}
        else
          token
        end
      else
        token
      end

    do_mark_type_alias_record_identifiers(
      rest,
      alias_lines,
      next_depth,
      next_in_field_type,
      [marked | acc]
    )
  end

  @spec alias_head_identifier_keys(term()) :: [{integer(), integer(), String.t()}]
  defp alias_head_identifier_keys(line_tokens) do
    line_tokens
    |> line_non_trivia_tokens()
    |> Enum.drop(3)
    |> Enum.take_while(&(&1.text != "="))
    |> Enum.filter(&(&1.class == "identifier"))
    |> Enum.map(&token_key/1)
  end

  @spec token_key(term()) :: {integer(), integer(), String.t()}
  defp token_key(%{line: line, column: column, text: text}), do: {line, column, text}

  @spec line_has_text?(term(), term()) :: boolean()
  defp line_has_text?(line_tokens, text) do
    Enum.any?(line_tokens, &(&1.text == text))
  end

  @spec first_token_column(term(), term()) :: integer() | nil
  defp first_token_column(line_tokens, text) do
    case Enum.find(line_tokens, &(&1.text == text)) do
      %{column: col} when is_integer(col) -> col
      _ -> nil
    end
  end

  @spec annotation_line_prefix_allows?(term()) :: boolean()
  defp annotation_line_prefix_allows?(line_tokens) do
    case Enum.find(line_tokens, &(not trivia_token?(&1))) do
      %{class: klass} when klass in ["identifier", "type_identifier", "field_identifier"] ->
        true

      %{class: "keyword", text: "port"} ->
        true

      %{class: "operator", text: "."} ->
        true

      %{class: "operator", text: text} when is_binary(text) ->
        operator_section_annotation_prefix?(text)

      _ ->
        false
    end
  end

  @spec operator_section_annotation_prefix?(term()) :: boolean()
  defp operator_section_annotation_prefix?(text) when is_binary(text) do
    String.starts_with?(text, "(") and String.ends_with?(text, ")") and String.length(text) > 1
  end

  @spec line_non_trivia_tokens(term()) :: [token()]
  defp line_non_trivia_tokens(line_tokens) do
    Enum.reject(line_tokens, &trivia_token?/1)
  end

  @spec trivia_token?(term()) :: boolean()
  defp trivia_token?(%{class: class}) when class in ["whitespace", "comment"], do: true
  defp trivia_token?(_), do: false

  @spec line_blank_or_comment_only?(term()) :: boolean()
  defp line_blank_or_comment_only?(line_tokens) do
    line_non_trivia_tokens(line_tokens) == []
  end

  @spec line_indented?(term()) :: boolean()
  defp line_indented?(line_tokens) do
    line_tokens
    |> line_non_trivia_tokens()
    |> case do
      [first | _] -> is_integer(first.column) and first.column > 1
      [] -> false
    end
  end

  @spec next_matching_lex_class(term(), term(), term()) :: {String.t() | nil, map()}
  defp next_matching_lex_class(state, line, token_text) do
    case Map.get(state, line, []) do
      [%{"text" => ^token_text} = tok | rest] ->
        {elmc_class(tok), Map.put(state, line, rest)}

      _ ->
        {nil, state}
    end
  end

  @spec elmc_class(term()) :: String.t()
  defp elmc_class(%{"type" => type}) do
    cond do
      String.ends_with?(type, "_kw") -> "keyword"
      type in ["int_lit", "float_lit"] -> "number"
      String.contains?(type, "string") or type == "char_lit" -> "string"
      type in ["upper_id", "upper_qid"] -> "type_identifier"
      type in ["lower_id", "lower_qid"] -> "identifier"
      String.ends_with?(type, "_id") or String.ends_with?(type, "_qid") -> "identifier"
      true -> "operator"
    end
  end

  @spec token_text_from_type(term()) :: String.t()
  defp token_text_from_type(type) when is_atom(type) do
    case type do
      :comma ->
        ","

      :colon ->
        ":"

      :lparen ->
        "("

      :rparen ->
        ")"

      :dotdot ->
        ".."

      :newline ->
        "\n"

      _ ->
        raw = Atom.to_string(type)

        if String.ends_with?(raw, "_kw") do
          String.trim_trailing(raw, "_kw")
        else
          raw
        end
    end
  end

  @spec compiler_diagnostic(term(), term(), term()) :: diagnostic()
  defp compiler_diagnostic(line, reason, source) do
    diagnostic = TokenizerParserMapper.compiler_lexer_fallback(line, reason)

    put_inferred_span(diagnostic, source)
  end

  @spec normalize_compiler_diagnostics(term(), term()) :: [diagnostic()]
  defp normalize_compiler_diagnostics(diagnostics, source) when is_list(diagnostics) do
    Enum.map(diagnostics, fn diag ->
      normalized = TokenizerParserMapper.compiler_parser_hint(diag)

      put_inferred_span(normalized, source)
    end)
  end

  @spec put_inferred_span(term(), term()) :: diagnostic()
  defp put_inferred_span(%{line: line, column: nil} = diagnostic, source)
       when is_integer(line) and line > 0 do
    source_line =
      source
      |> String.split("\n", trim: false)
      |> Enum.at(line - 1, "")

    {column, end_column} = infer_span_from_message(source_line, diagnostic.message)

    diagnostic
    |> Map.put(:column, column)
    |> Map.put(:end_column, end_column)
  end

  defp put_inferred_span(diagnostic, _source), do: diagnostic

  @spec infer_span_from_message(term(), term()) :: {pos_integer(), pos_integer()}
  defp infer_span_from_message(source_line, message) do
    hinted = hinted_token_from_message(message)

    cond do
      is_binary(hinted) and hinted != "" ->
        case :binary.match(source_line, hinted) do
          {idx, len} ->
            start_col = idx + 1
            end_col = max(start_col, start_col + len - 1)
            {start_col, end_col}

          :nomatch ->
            col = first_non_whitespace_column(source_line)
            {col, col}
        end

      true ->
        col = first_non_whitespace_column(source_line)
        {col, col}
    end
  end

  @spec hinted_token_from_message(term()) :: String.t() | nil
  defp hinted_token_from_message(message) do
    captures =
      Regex.scan(~r/~c"([^"]+)"/, message)
      |> Enum.map(fn [_, token] -> token end)
      |> Enum.reject(&(&1 == "syntax error before: "))

    List.last(captures)
  end

  @spec first_non_whitespace_column(term()) :: pos_integer()
  defp first_non_whitespace_column(source_line) do
    source_line
    |> String.to_charlist()
    |> Enum.find_index(&(&1 not in [?\s, ?\t]))
    |> case do
      nil -> 1
      idx -> idx + 1
    end
  end

  @spec elm_ex_root() :: String.t()
  defp elm_ex_root do
    Application.get_env(:ide, Ide.Compiler, [])
    |> Keyword.fetch!(:elm_ex_root)
  end
end
