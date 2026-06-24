defmodule IdeWeb.WorkspaceLive.EditorSupport.Types do
  @moduledoc false

  alias Ide.Debugger.Types, as: DebuggerTypes
  alias Ide.Formatter.Types, as: FormatterTypes
  alias Ide.Tokenizer.Types, as: TokenizerTypes

  @type socket :: Phoenix.LiveView.Socket.t()
  @type phoenix_form :: Phoenix.HTML.Form.t()

  @type async_token :: pos_integer() | nil

  @type context_menu_state :: %{
          required(:x) => non_neg_integer(),
          required(:y) => non_neg_integer(),
          required(:offset) => non_neg_integer(),
          required(:readonly) => boolean()
        }

  @type editor_state :: %{
          required(:cursor_offset) => non_neg_integer(),
          required(:scroll_top) => non_neg_integer(),
          required(:scroll_left) => non_neg_integer(),
          required(:active_diagnostic_index) => non_neg_integer()
        }

  @type editor_restore_state :: %{
          optional(:cursor_offset) => non_neg_integer(),
          optional(:scroll_top) => non_neg_integer(),
          optional(:scroll_left) => non_neg_integer(),
          optional(:active_diagnostic_index) => non_neg_integer()
        }

  @type tab :: %{
          required(:id) => String.t(),
          required(:source_root) => String.t(),
          required(:rel_path) => String.t(),
          required(:content) => String.t(),
          required(:saved_content) => String.t(),
          required(:dirty) => boolean(),
          required(:read_only) => boolean(),
          optional(:editor_state) => editor_state()
        }

  @typedoc """
  LiveView save payload for editor tab content (`content` or nested `editor.content`).
  """
  @type tab_save_params :: %{
          optional(String.t()) => String.t() | %{optional(String.t()) => String.t()}
        }

  @type tabs :: [tab()]
  @type project :: Ide.Projects.Project.t() | nil

  @type edit_patch :: %{
          required(:replace_from) => non_neg_integer(),
          required(:replace_to) => non_neg_integer(),
          required(:inserted_text) => String.t(),
          optional(:cursor_start) => non_neg_integer(),
          optional(:cursor_end) => non_neg_integer()
        }

  @type fold_range :: %{
          required(:start_line) => pos_integer(),
          required(:end_line) => pos_integer()
        }

  @type diagnostic :: TokenizerTypes.diagnostic()
  @type tokenizer_token :: TokenizerTypes.token()
  @type parser_payload :: TokenizerTypes.parser_payload() | nil
  @type format_result :: FormatterTypes.format_result()
  @type tab_updater :: (tab() -> tab())

  @type save_status :: :inactive | :unchanged | :applied | :skipped

  @type save_prep_meta :: %{
          required(:status) => save_status(),
          required(:rel_path) => String.t()
        }

  @type save_prep_result :: {String.t(), String.t(), String.t() | nil, save_prep_meta()}

  @type modify_error :: :read_only_file | :protected_file
  @type format_error ::
          FormatterTypes.parse_error() | atom() | String.t() | {atom(), String.t() | atom()}
  @type diagnostic_field :: String.t() | integer() | atom() | boolean() | nil
  @type wire_input :: String.t() | integer() | boolean() | nil
  @type kw_value :: DebuggerTypes.wire_input() | [DebuggerTypes.wire_input()] | atom()

  @type token_summary :: %{
          required(:total) => non_neg_integer(),
          required(:classes) => [{String.t(), non_neg_integer()}]
        }

  @type tokenize_result :: %{
          required(:tokens) => [tokenizer_token()],
          required(:summary) => token_summary() | nil,
          required(:diagnostics) => [diagnostic()],
          required(:formatter_parser_payload) => parser_payload()
        }

  @type diagnostics_by_line :: %{pos_integer() => [diagnostic()]}
end
