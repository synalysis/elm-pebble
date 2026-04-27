defmodule Ide.Diagnostics.TokenizerParserMapper do
  @moduledoc """
  Maps tokenizer/parser events to a canonical Elm-style diagnostic shape.
  """

  alias Ide.Diagnostics.ElmSyntaxCatalog

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

  @spec unterminated_block_comment(integer(), integer(), integer(), integer()) :: diagnostic()
  def unterminated_block_comment(line, column, end_line, end_column) do
    base(:endless_comment, "warning", "tokenizer", line, column,
      end_line: end_line,
      end_column: end_column
    )
  end

  @spec unterminated_string(integer(), integer(), integer(), integer()) :: diagnostic()
  def unterminated_string(line, column, end_line, end_column) do
    base(:endless_string_single, "warning", "tokenizer", line, column,
      end_line: end_line,
      end_column: end_column
    )
  end

  @spec unterminated_multiline_string(integer(), integer(), integer(), integer()) :: diagnostic()
  def unterminated_multiline_string(line, column, end_line, end_column) do
    base(:endless_string_multi, "warning", "tokenizer", line, column,
      end_line: end_line,
      end_column: end_column
    )
  end

  @spec invalid_char_literal(integer(), integer()) :: diagnostic()
  def invalid_char_literal(line, column) do
    base(:missing_single_quote, "warning", "tokenizer", line, column)
  end

  @spec unclosed_delimiter(String.t(), map()) :: diagnostic()
  def unclosed_delimiter(expected, token) when is_binary(expected) and is_map(token) do
    unclosed_delimiter(expected, token, :unclosed_delimiter)
  end

  @spec unclosed_delimiter(String.t(), map(), atom()) :: diagnostic()
  def unclosed_delimiter(expected, token, title_id)
      when is_binary(expected) and is_map(token) and is_atom(title_id) do
    base(
      title_id,
      "warning",
      "tokenizer",
      Map.get(token, :line),
      Map.get(token, :column),
      detail: "I expected `#{expected}` before the end of this expression."
    )
  end

  @spec unexpected_closing_delimiter(String.t(), map()) :: diagnostic()
  def unexpected_closing_delimiter(closing, token) when is_binary(closing) and is_map(token) do
    base(
      :unexpected_closing_delimiter,
      "warning",
      "tokenizer",
      Map.get(token, :line),
      Map.get(token, :column),
      detail: "I was not expecting the closing delimiter `#{closing}` at this location."
    )
  end

  @spec unexpected_capital_field(map()) :: diagnostic()
  def unexpected_capital_field(token) when is_map(token) do
    base(
      :unexpected_capital_letter,
      "warning",
      "tokenizer",
      Map.get(token, :line),
      Map.get(token, :column),
      detail: "Record field names must start with a lower-case letter.",
      end_line: Map.get(token, :line),
      end_column: Map.get(token, :column, 1) + String.length(Map.get(token, :text, ""))
    )
  end

  @spec compiler_parser_hint(map()) :: diagnostic()
  def compiler_parser_hint(diag) when is_map(diag) do
    source_name = get(diag, :source, "elmc_parser")
    line = get(diag, :line)
    reason = get(diag, :message, "Parser reported an issue.")
    title = get(diag, :elm_title) || infer_elm_title(reason)
    detail = get(diag, :detail) || reason
    column = get(diag, :column)

    from_title(title, "warning", "tokenizer/#{source_name}", line, column, detail: detail)
  end

  @spec compiler_lexer_fallback(integer() | nil, term()) :: diagnostic()
  def compiler_lexer_fallback(line, reason) do
    base(:unexpected_character, "warning", "tokenizer/elmc", line, nil,
      detail: normalize_value(reason)
    )
  end

  @spec unknown_escape(integer(), integer(), String.t()) :: diagnostic()
  def unknown_escape(line, column, escape) do
    base(:unknown_escape, "warning", "tokenizer", line, column,
      detail: "I do not recognize the escape sequence `\\#{escape}`."
    )
  end

  @spec bad_unicode_escape(integer(), integer(), String.t()) :: diagnostic()
  def bad_unicode_escape(line, column, detail) do
    base(:bad_unicode_escape, "warning", "tokenizer", line, column, detail: detail)
  end

  @spec weird_number(integer(), integer(), String.t()) :: diagnostic()
  def weird_number(line, column, detail) do
    base(:weird_number, "warning", "tokenizer", line, column, detail: detail)
  end

  @spec weird_hexidecimal(integer(), integer(), String.t()) :: diagnostic()
  def weird_hexidecimal(line, column, detail) do
    base(:weird_hexidecimal, "warning", "tokenizer", line, column, detail: detail)
  end

  @spec leading_zeros(integer(), integer(), String.t()) :: diagnostic()
  def leading_zeros(line, column, detail) do
    base(:leading_zeros, "warning", "tokenizer", line, column, detail: detail)
  end

  @spec needs_double_quotes(integer(), integer(), String.t()) :: diagnostic()
  def needs_double_quotes(line, column, detail) do
    base(:needs_double_quotes, "warning", "tokenizer", line, column, detail: detail)
  end

  @spec from_title(
          String.t() | atom(),
          String.t(),
          String.t(),
          integer() | nil,
          integer() | nil,
          keyword()
        ) ::
          diagnostic()
  def from_title(title, severity, source, line, column, extra \\ [])

  def from_title(title, severity, source, line, column, extra)
      when is_binary(title) and is_binary(severity) and is_binary(source) do
    id = ElmSyntaxCatalog.title_to_id(title)
    extra = Keyword.put_new(extra, :detail, Keyword.get(extra, :detail, ""))
    base(id, severity, source, line, column, extra)
  end

  def from_title(id, severity, source, line, column, extra)
      when is_atom(id) and is_binary(severity) and is_binary(source) and is_list(extra) do
    extra = Keyword.put_new(extra, :detail, Keyword.get(extra, :detail, ""))
    base(id, severity, source, line, column, extra)
  end

  @spec base(term(), term(), term(), term(), term(), term()) :: term()
  defp base(id, severity, source, line, column, extra \\ []) do
    entry = ElmSyntaxCatalog.entry(id) || %{}
    detail = Keyword.get(extra, :detail, "")

    %{
      severity: severity,
      source: source,
      message: ElmSyntaxCatalog.build_message(id, %{detail: detail}),
      line: line,
      column: column,
      catalog_id: id,
      catalog_version: ElmSyntaxCatalog.catalog_version(),
      elm_title: Map.get(entry, :title),
      elm_source_title: Map.get(entry, :source_title),
      elm_hint: Map.get(entry, :hint),
      elm_example: Map.get(entry, :example),
      elm_span_semantics: Map.get(entry, :span_semantics)
    }
    |> maybe_put(:end_line, Keyword.get(extra, :end_line))
    |> maybe_put(:end_column, Keyword.get(extra, :end_column))
  end

  @spec maybe_put(term(), term(), term()) :: term()
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @spec get(term(), term(), term()) :: term()
  defp get(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key), default)
  end

  @spec normalize_value(term()) :: term()
  defp normalize_value(value) when is_binary(value), do: value
  defp normalize_value(value) when is_list(value), do: List.to_string(value)
  defp normalize_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_value(value) when is_number(value), do: to_string(value)
  defp normalize_value(value), do: inspect(value)

  @spec infer_elm_title(term()) :: term()
  defp infer_elm_title(reason) when is_binary(reason) do
    cond do
      String.contains?(reason, "expecting module name") ->
        :expecting_module_name

      String.contains?(reason, "expecting import name") ->
        :expecting_import_name

      String.contains?(reason, "expecting import alias") ->
        :expecting_import_alias

      String.contains?(reason, "unfinished import") ->
        :unfinished_import

      String.contains?(reason, "problem in exposing") ->
        :problem_in_exposing

      String.contains?(reason, "unfinished exposing") ->
        :unfinished_exposing

      String.contains?(reason, "expecting type name") ->
        :expecting_type_name

      String.contains?(reason, "expecting type alias name") ->
        :expecting_type_alias_name

      String.contains?(reason, "missing expression") ->
        :missing_expression

      String.contains?(reason, "missing arrow") ->
        :missing_arrow

      String.contains?(reason, "syntax error before:") and String.contains?(reason, "'->'") ->
        :unexpected_arrow

      String.contains?(reason, "syntax error before:") and String.contains?(reason, "'='") ->
        :unexpected_equals

      String.contains?(reason, "syntax error before:") and String.contains?(reason, "','") ->
        :unexpected_comma

      String.contains?(reason, "syntax error before:") and String.contains?(reason, "';'") ->
        :unexpected_semicolon

      String.contains?(reason, "syntax error before:") ->
        :unexpected_symbol

      String.contains?(reason, "Invalid type variable") ->
        :problem_in_type_alias

      String.contains?(reason, "Invalid type declaration header") ->
        :problem_in_type_alias

      String.contains?(reason, "Invalid custom type constructor") ->
        :problem_in_custom_type

      String.contains?(reason, "Invalid port declaration header") ->
        :port_problem

      String.contains?(reason, "illegal characters") ->
        :unexpected_character

      true ->
        :syntax_problem
    end
  end

  defp infer_elm_title(_), do: :syntax_problem
end
