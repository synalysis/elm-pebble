defmodule IdeWeb.WorkspaceLive.EditorSupport.Types do
  @moduledoc false

  alias Ide.Projects.Project

  @type socket :: Phoenix.LiveView.Socket.t()
  @type tab :: map()
  @type tabs :: [tab()]
  @type project :: Project.t() | nil
  @type edit_patch :: %{
          required(:replace_from) => non_neg_integer(),
          required(:replace_to) => non_neg_integer(),
          required(:inserted_text) => String.t(),
          optional(:cursor_start) => non_neg_integer(),
          optional(:cursor_end) => non_neg_integer()
        }
  @type fold_range :: %{required(:start_line) => pos_integer(), required(:end_line) => pos_integer()}
  @type diagnostic :: map()
  @type tokenizer_token :: map()
  @type parser_payload :: map() | nil
  @type format_result :: map()
  @type tab_updater :: (tab() -> tab())
  @type save_prep_result :: {String.t(), String.t(), String.t() | nil, map()}
  @type modify_error :: :read_only_file | :protected_file
  @type editor_state :: map()
  @type wire_input :: String.t() | integer() | boolean() | nil
  @type format_error :: map() | atom() | String.t() | {atom(), term()}
  @type diagnostic_field :: String.t() | integer() | atom() | boolean() | nil
  @type kw_value :: String.t() | integer() | boolean() | list() | map() | atom() | nil
end
