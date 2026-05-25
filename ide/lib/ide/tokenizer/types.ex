defmodule Ide.Tokenizer.Types do
  @moduledoc """
  Shared types for tokenizer scan state, tokens, and diagnostics.
  """

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
          optional(:detail) => String.t(),
          optional(:elm_source_title) => String.t(),
          optional(:elm_hint) => String.t(),
          optional(:elm_example) => String.t(),
          optional(:elm_span_semantics) => atom()
        }

  @type parser_payload :: %{
          diagnostics: [map()],
          metadata: Ide.Formatter.Semantics.HeaderMetadata.metadata(),
          source_hash: integer(),
          fallback?: boolean()
        }

  @type source :: String.t()
  @type line :: pos_integer()
  @type column :: pos_integer()
  @type tokens_acc :: [token()]
  @type diagnostics_acc :: [diagnostic()]
  @type scan_result :: {tokens_acc(), diagnostics_acc()}
  @type char_pred :: (String.t() -> as_boolean(term()))
  @type line_col :: {integer(), integer()}
  @type unterminated_kind :: atom()

  @type compiler_lex_ok :: %{
          tokens: [map()],
          diagnostics: [diagnostic()],
          parser_payload: parser_payload() | nil
        }

  @type compiler_lex_result :: {:ok, compiler_lex_ok()} | {:error, map()}

  @type run_elm_ex_lex_result ::
          {:ok, list(), [diagnostic()], parser_payload() | nil} | {:error, map()}

  @type tokenize_result :: %{
          tokens: [token()],
          diagnostics: [diagnostic()],
          formatter_parser_payload: parser_payload() | nil
        }

  @type tokens :: [token()]
  @type token_key :: {integer(), integer(), String.t()}
  @type lines_map :: %{optional(integer()) => tokens()}
  @type annotation_context :: %{optional(integer()) => non_neg_integer()}
  @type elmc_token :: map()
  @type indexed_lines :: [{String.t(), pos_integer()}]
  @type delim_stack_entry :: {String.t(), token()}
  @type delimiter_stack :: [delim_stack_entry()]
  @type char_code :: non_neg_integer()
  @type compact_split :: {:split, String.t(), String.t()} | :no_split
  @type take_literal_result :: {String.t(), String.t(), boolean()}
  @type elmc_lex_state :: %{optional(integer()) => [elmc_token()]}
  @type ensure_loaded_error :: String.t()
  @type parser_reason :: atom() | String.t() | map() | tuple()

  @type parser_diagnostic_map :: %{
          required(:source) => String.t(),
          required(:line) => integer() | nil,
          optional(:column) => integer() | nil,
          required(:message) => String.t(),
          optional(:elm_title) => atom(),
          optional(:detail) => String.t()
        }

  @type elmc_raw_token ::
          {atom(), integer(), elmc_value()} | {atom(), integer()} | map() | atom() | String.t()
  @type elmc_value :: String.t() | charlist() | atom() | number() | boolean() | list() | map() | nil
end
