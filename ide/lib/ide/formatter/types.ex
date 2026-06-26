defmodule Ide.Formatter.Types do
  @moduledoc """
  Shared types for formatter pipelines, string transforms, and edit operations.
  """

  alias Ide.Formatter.Semantics.HeaderMetadata
  alias Ide.Formatter.Semantics.Parse
  alias Ide.Tokenizer.Types, as: TokenizerTypes

  @type source :: String.t()
  @type source_line :: String.t()
  @type format_opts :: keyword()
  @type parse_metadata_error :: %{
          required(:line) => integer(),
          required(:column) => pos_integer(),
          required(:message) => String.t()
        }

  @type parse_error :: diagnostic() | parse_metadata_error()
  @type parse_payload :: Parse.parse_payload()
  @type metadata :: HeaderMetadata.metadata()
  @type format_token :: TokenizerTypes.token()

  @type diagnostic :: %{
          severity: String.t(),
          source: String.t(),
          message: String.t(),
          line: integer() | nil,
          column: integer() | nil
        }

  @type format_details :: %{
          optional(:parser_payload_reused?) => boolean(),
          optional(:pipeline) => String.t(),
          optional(:backend) => atom(),
          optional(:command) => String.t()
        }

  @type format_result :: %{
          formatted_source: String.t(),
          changed?: boolean(),
          diagnostics: [diagnostic()],
          formatter: String.t(),
          details: format_details()
        }
  @type edit_result :: %{
          next_content: String.t(),
          cursor_start: non_neg_integer(),
          cursor_end: non_neg_integer()
        }

  @type split_pair :: {String.t(), String.t()}
  @type split_result :: split_pair() | :error
  @type take_until_result :: {:ok, String.t(), String.t()} | :error
  @type line_list :: [source_line()]
  @type list_split :: :no_change | {:split, source_line(), source_line()}
  @type enter_split :: {:ok, source(), non_neg_integer()} | :error
  @type line_col :: {pos_integer(), pos_integer()}
  @type char_or_nil :: String.t() | nil
  @type offset :: non_neg_integer()

  @type parity_baseline :: %{
          optional(String.t()) => String.t() | non_neg_integer() | float()
        }

  @type parity_phase_gate :: :disabled | :empty | :skipped | :failed | :passed

  @type multiline_if_layout :: %{
          required(:else_indent) => non_neg_integer(),
          required(:branch_indent) => non_neg_integer(),
          optional(:phase) => :then | :waiting_else | :else
        }

  @type non_empty_line_context :: %{
          required(:line) => source_line(),
          required(:trimmed) => String.t(),
          required(:indent) => non_neg_integer()
        }

  @type union_align_state :: %{
          required(:in_type_decl) => boolean(),
          required(:declaration_indent) => non_neg_integer(),
          required(:pipe_indent) => non_neg_integer() | nil,
          required(:pending_blanks) => non_neg_integer()
        }

  @type mix_task_args :: [String.t()]
end
