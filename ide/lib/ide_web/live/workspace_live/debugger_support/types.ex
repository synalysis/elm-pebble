defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Types do
  @moduledoc false
  @dialyzer :no_match

  @type socket :: Phoenix.LiveView.Socket.t()
  @type maybe_non_neg_integer :: non_neg_integer() | nil
  @type timeline_kind :: :all | :protocol | :update | :render | :lifecycle | :other
  @type event_type_counts :: [{String.t(), non_neg_integer()}]
  @type event_summary :: %{
          seq: non_neg_integer(),
          type: String.t(),
          target: String.t() | nil,
          message: String.t() | nil
        }
  @type highlight_fragment :: %{text: String.t(), match?: boolean()}
  @type protocol_row :: %{
          seq: non_neg_integer(),
          kind: String.t(),
          from: String.t() | nil,
          to: String.t() | nil,
          message: String.t() | nil
        }
  @type update_message_row :: %{
          seq: non_neg_integer(),
          target: String.t() | nil,
          message: String.t() | nil
        }
  @type debugger_row :: %{
          seq: non_neg_integer(),
          debugger_seq: non_neg_integer(),
          raw_seq: non_neg_integer(),
          type: String.t(),
          target: String.t(),
          message: String.t(),
          message_source: String.t() | nil,
          selected_runtime: map() | nil,
          other_runtime: map() | nil,
          watch_runtime: map() | nil,
          companion_runtime: map() | nil,
          phone_runtime: map() | nil
        }
  @type render_event_row :: %{
          seq: non_neg_integer(),
          target: String.t() | nil,
          root: String.t() | nil
        }
  @type lifecycle_row :: %{
          seq: non_neg_integer(),
          type: String.t(),
          summary: String.t()
        }
  @type replay_preview_row :: %{
          seq: non_neg_integer(),
          target: String.t(),
          message: String.t()
        }
  @type replay_compare :: %{
          status: :none | :match | :mismatch,
          reason: String.t() | nil,
          preview_count: non_neg_integer(),
          applied_count: non_neg_integer(),
          mismatch_preview: replay_preview_row() | nil,
          mismatch_applied: replay_preview_row() | nil
        }

  @type wire_input :: String.t() | integer() | nil
  @type rendered_node :: map()
  @type view_tree :: map()
  @type events :: [map()]
  @type runtime_value :: map() | list() | String.t() | number() | boolean() | atom() | nil
  @type debugger_state_map :: map()
end
