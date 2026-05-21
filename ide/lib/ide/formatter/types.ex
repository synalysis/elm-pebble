defmodule Ide.Formatter.Types do
  @moduledoc """
  Shared types for formatter pipelines, string transforms, and edit operations.
  """

  alias Ide.Formatter.Semantics.HeaderMetadata
  alias Ide.Formatter.Semantics.Parse

  @type source :: String.t()
  @type source_line :: String.t()
  @type format_opts :: keyword()
  @type parse_error :: map()
  @type parse_payload :: Parse.parse_payload()
  @type metadata :: HeaderMetadata.metadata()
  @type diagnostic :: %{
          severity: String.t(),
          source: String.t(),
          message: String.t(),
          line: integer() | nil,
          column: integer() | nil
        }

  @type format_result :: %{
          formatted_source: String.t(),
          changed?: boolean(),
          diagnostics: [diagnostic()],
          formatter: String.t(),
          details: map()
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

  @type mix_task_args :: [String.t()]
end
