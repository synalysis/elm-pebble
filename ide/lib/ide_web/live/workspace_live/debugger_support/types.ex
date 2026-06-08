defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Types do
  @moduledoc false
  @dialyzer :no_match

  alias Ide.Debugger.RuntimeArtifacts.Types, as: ArtifactTypes
  alias Ide.Debugger.Types, as: DebuggerTypes

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
  @type execution_model :: DebuggerTypes.execution_model() | nil

  @type debugger_row :: %{
          optional(:watch) => execution_model(),
          optional(:companion) => execution_model(),
          optional(:phone) => execution_model(),
          optional(:payload) => wire_map(),
          required(:seq) => non_neg_integer(),
          required(:debugger_seq) => non_neg_integer(),
          required(:raw_seq) => non_neg_integer(),
          required(:type) => String.t(),
          required(:target) => String.t(),
          required(:message) => String.t(),
          required(:message_source) => String.t() | nil,
          required(:selected_runtime) => execution_model(),
          required(:other_runtime) => execution_model(),
          required(:watch_runtime) => execution_model(),
          required(:companion_runtime) => execution_model(),
          required(:phone_runtime) => execution_model()
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
  @type replay_preview_row :: DebuggerTypes.ReplayEventPayload.replay_preview_row()

  @type replay_compare :: %{
          status: :none | :match | :mismatch,
          reason: String.t() | nil,
          preview_count: non_neg_integer(),
          applied_count: non_neg_integer(),
          mismatch_preview: replay_preview_row() | nil,
          mismatch_applied: replay_preview_row() | nil
        }

  @type wire_input :: String.t() | integer() | nil
  @type wire_map :: DebuggerTypes.wire_map()
  @type wire_value :: DebuggerTypes.wire_value()
  @type view_tree :: DebuggerTypes.view_output_tree()
  @type rendered_node :: DebuggerTypes.view_output_tree()
  @type view_output_row :: DebuggerTypes.view_output_row()
  @type view_node :: view_output_row() | view_tree()
  @type svg_op :: view_output_row() | DebuggerTypes.wire_map()
  @type resource_index_map :: ArtifactTypes.resource_indices()
  @type svg_style :: DebuggerTypes.wire_map()
  @type svg_style_stack :: [svg_style()]
  @type runtime_input :: DebuggerTypes.execution_model() | nil
  @type model_map :: DebuggerTypes.app_model() | DebuggerTypes.execution_model()

  @type bounds_map :: %{
          optional(:x) => integer(),
          optional(:y) => integer(),
          optional(:w) => integer(),
          optional(:h) => integer(),
          optional(:width) => integer(),
          optional(:height) => integer(),
          optional(String.t()) => integer() | float()
        }

  @type compact_scene_op :: %{
          optional(:op) => svg_op(),
          optional(:bounds) => bounds_map() | nil,
          optional(:hash) => String.t()
        }

  @type compact_scene :: %{
          optional(:version) => pos_integer(),
          optional(:ops) => [compact_scene_op()],
          optional(:hash) => String.t()
        }

  @type compact_scene_diff :: %{
          required(:changed?) => boolean(),
          required(:dirty_bounds) => [bounds_map()],
          optional(:previous_hash) => String.t(),
          optional(:current_hash) => String.t()
        }

  @type unresolved_row :: %{
          optional(:node_type) => String.t(),
          optional(:provided_int_count) => non_neg_integer(),
          optional(:required_int_count) => non_neg_integer(),
          optional(atom()) => wire_value(),
          optional(String.t()) => wire_value()
        }

  @type flattened_rendered_node :: %{
          required(:path) => String.t(),
          required(:type) => String.t(),
          optional(:label) => String.t() | nil,
          optional(:bounds) => bounds_map() | nil,
          optional(:source) => String.t() | nil
        }

  @type hash_input :: DebuggerTypes.wire_map() | [String.t()]

  @type timeline_event :: DebuggerTypes.runtime_event() | DebuggerTypes.debugger_event()
  @type events :: [timeline_event()]

  @type replay_metadata :: %{
          optional(:seq) => non_neg_integer(),
          optional(:target) => String.t() | nil,
          optional(:replay_source) => String.t() | nil,
          optional(:requested_count) => non_neg_integer() | nil,
          optional(:replayed_count) => non_neg_integer() | nil,
          optional(:cursor_seq) => non_neg_integer() | nil,
          optional(:replay_telemetry) => DebuggerTypes.wire_map(),
          optional(:replay_target_counts) => DebuggerTypes.ReplayEventPayload.count_map(),
          optional(:replay_message_counts) => DebuggerTypes.ReplayEventPayload.count_map(),
          optional(:replay_preview) => [replay_preview_row()]
        }

  @type diagnostics_preview_result :: %{
          required(:source) => String.t(),
          required(:rows) => [DebuggerTypes.elmc_diagnostic_row()]
        }

  @type surface_contracts_at_cursor :: %{
          required(:watch) => DebuggerTypes.elm_introspect() | nil,
          required(:companion) => DebuggerTypes.elm_introspect() | nil,
          required(:phone) => DebuggerTypes.elm_introspect() | nil
        }

  @type surface_fingerprints_at_cursor :: %{
          required(:watch) => DebuggerTypes.runtime_fingerprint() | nil,
          required(:companion) => DebuggerTypes.runtime_fingerprint() | nil,
          required(:phone) => DebuggerTypes.runtime_fingerprint() | nil
        }

  @type trigger_button_row :: %{
          optional(:id) => String.t(),
          optional(:label) => String.t(),
          optional(:trigger) => String.t(),
          optional(:trigger_display) => String.t(),
          optional(:target) => String.t(),
          optional(:message) => String.t(),
          optional(:source) => String.t(),
          optional(:button) => wire_value(),
          optional(:button_event) => wire_value(),
          optional(:interval_ms) => wire_value(),
          optional(:declared_interval_ms) => wire_value(),
          optional(:model_active?) => boolean(),
          optional(:injection_supported?) => boolean(),
          optional(atom()) => wire_value(),
          optional(String.t()) => wire_value()
        }

  @type cursor_snapshot_runtime :: %{
          required(:watch) => execution_model(),
          required(:companion) => execution_model(),
          required(:phone) => execution_model()
        }

  @type debugger_assigns_result :: %{
          required(:rows) => [debugger_row()],
          required(:cursor_seq) => maybe_non_neg_integer(),
          required(:selected) => debugger_row() | nil,
          required(:watch_runtime) => execution_model(),
          required(:companion_runtime) => execution_model(),
          required(:watch_view_runtime) => execution_model()
        }

  @type runtime_value :: DebuggerTypes.wire_value()
  @type debugger_state_map :: DebuggerTypes.runtime_state()
  @type wire_payload :: DebuggerTypes.debugger_timeline_payload()
end
