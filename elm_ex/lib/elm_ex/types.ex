defmodule ElmEx.Types do
  @moduledoc """
  Shared types used across elm_ex packages.
  """

  alias ElmEx.Types.ElmReport

  @type module_exposing :: nil | String.t() | [String.t()]

  @type package_versions :: %{String.t() => String.t()}

  @type dependency_sections :: %{
          optional(String.t()) => package_versions()
        }

  @type detail_value :: atom() | boolean() | number() | String.t() | nil

  @type parse_error_detail :: %{
          optional(atom()) => detail_value() | parse_error_detail() | [detail_value()],
          optional(String.t()) => detail_value() | parse_error_detail() | [detail_value()]
        }

  @type lexer_line :: non_neg_integer()

  @type lexer_keyword_token ::
          {:module_kw, lexer_line()}
          | {:effect_kw, lexer_line()}
          | {:import_kw, lexer_line()}
          | {:as_kw, lexer_line()}
          | {:exposing_kw, lexer_line()}
          | {:port_kw, lexer_line()}

  @type lexer_punct_token ::
          {:dotdot, lexer_line()}
          | {:comma, lexer_line()}
          | {:lparen, lexer_line()}
          | {:rparen, lexer_line()}
          | {:colon, lexer_line()}
          | {:dot, lexer_line()}
          | {:newline, lexer_line()}

  @type lexer_id_token ::
          {:upper_id, lexer_line(), String.t()}
          | {:lower_id, lexer_line(), String.t()}

  @type lexer_token :: lexer_keyword_token() | lexer_punct_token() | lexer_id_token()

  @type parse_yecc_tail :: String.t() | charlist() | lexer_token()

  @type parse_yecc_error :: {integer(), module(), [parse_yecc_tail()]}

  @type expr_yecc_error :: {pos_integer(), :elm_ex_expr_parser, [String.t() | charlist()]}

  @type decl_union_constructor :: {:constructor, String.t(), String.t() | nil}

  @type decl_parser_output ::
          {:function_signature, String.t(), String.t()}
          | {:port_signature, String.t(), String.t()}
          | {:function_header, String.t(), [String.t()]}
          | {:type_alias, String.t()}
          | {:union_start, String.t(), :none}
          | {:union_start_many, String.t(), [decl_union_constructor()]}
          | {:union_constructors, [decl_union_constructor()]}

  @type parse_token :: lexer_token() | expr_yecc_error() | parse_yecc_error()

  @type parse_reason ::
          atom()
          | {:illegal, String.t() | [char() | integer()]}
          | parse_error_detail()
          | parse_token()

  @type elm_json_field_map :: %{optional(String.t()) => json_field()}

  @type json_field :: String.t() | integer() | boolean() | list() | elm_json_field_map() | nil

  @type elm_message_part ::
          String.t()
          | %{optional(atom()) => String.t() | boolean()}
          | [elm_message_part()]

  @type elm_report :: ElmReport.t() | [ElmReport.t()]

  @type parse_error_reason ::
          atom()
          | expr_yecc_error()
          | parse_yecc_error()
          | String.t()
          | parse_token()

  @typedoc "Decoded `elm.json` project metadata (string keys)."
  @type elm_json :: %{optional(String.t()) => json_field()}
end
