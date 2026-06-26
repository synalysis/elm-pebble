defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Types do
  @moduledoc false
  @dialyzer :no_match

  alias Ide.Debugger.RuntimeArtifacts.Types, as: ArtifactTypes
  alias Ide.Debugger.Types, as: DebuggerTypes
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types.NormalizedSvg

  @type debugger_timeline_mode :: String.t()
  @type debugger_surface_target :: String.t()
  @type debugger_event :: DebuggerTypes.debugger_event()
  @type debugger_row_source :: debugger_state_map() | events() | nil
  @type debugger_row_wire :: debugger_event() | wire_map()
  @type elmc_lifecycle_payload :: DebuggerTypes.event_payload()

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
          optional(:payload) => DebuggerTypes.event_payload(),
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
  @type replay_preview_row :: DebuggerTypes.replay_preview_row()

  @type replay_compare_status :: :none | :match | :mismatch
  @type replay_compare_reason :: String.t() | nil
  @type replay_drift_severity :: :none | :mild | :medium | :high
  @type replay_surface_target :: String.t()
  @type replay_preview_target :: String.t()

  @type replay_compare :: %{
          status: replay_compare_status(),
          reason: replay_compare_reason(),
          preview_count: non_neg_integer(),
          applied_count: non_neg_integer(),
          mismatch_preview: replay_preview_row() | nil,
          mismatch_applied: replay_preview_row() | nil
        }

  @type wire_input :: String.t() | integer() | nil
  @type wire_map :: DebuggerTypes.wire_map()
  @type wire_string_map :: DebuggerTypes.wire_string_map()
  @type wire_value :: DebuggerTypes.wire_value()
  @type view_tree :: DebuggerTypes.view_output_tree()
  @type rendered_node :: DebuggerTypes.view_output_tree()

  @typedoc "Recursive runtime model value shown in the debugger model tree."
  @type model_tree_node ::
          wire_value()
          | DebuggerTypes.protocol_ctor_value()
          | %{optional(String.t()) => model_tree_node()}
          | [model_tree_node()]

  @type view_output_row :: DebuggerTypes.view_output_row()
  @type view_node :: view_output_row() | view_tree()
  @type runtime_input :: DebuggerTypes.execution_model() | nil
  @type model_map :: DebuggerTypes.app_model() | DebuggerTypes.execution_model()

  @typedoc "Flattened draw op from view_output; fields may use atom or string keys."
  @type draw_op_map :: view_output_row() | wire_map()

  @typedoc "Evaluation env for preview text resolution (`%{\"model\" => model}`)."
  @type preview_eval_env :: %{
          optional(:model) => model_map(),
          optional(String.t()) => wire_value() | model_map()
        }

  @type svg_op :: NormalizedSvg.svg_op()
  @type resource_index_map :: ArtifactTypes.resource_indices()
  @type svg_style :: NormalizedSvg.style()
  @type svg_style_stack :: [svg_style()]

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
          optional(:hash) => String.t(),
          optional(String.t()) => wire_value()
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
          optional(String.t()) => wire_value()
        }

  @type animation_hydration_fields :: %{
          required(:href) => String.t(),
          required(:width) => non_neg_integer(),
          required(:height) => non_neg_integer(),
          required(:play_count) => non_neg_integer(),
          required(:anim_id) => String.t()
        }

  @type resource_ctor_ref :: String.t() | atom() | DebuggerTypes.protocol_ctor_value()

  @type svg_path :: %{
          required(:points) => [[integer()]],
          required(:offset_x) => integer(),
          required(:offset_y) => integer(),
          required(:rotation) => integer()
        }

  @type path_payload :: %{
          optional(:points) => [{integer(), integer()}],
          optional(:offset_x) => integer(),
          optional(:offset_y) => integer(),
          optional(:rotation) => integer()
        }

  @type group_style_map :: DebuggerTypes.wire_string_map()
  @type elm_introspect :: Ide.Debugger.Types.elm_introspect()

  @type flattened_rendered_node :: %{
          required(:path) => String.t(),
          required(:type) => String.t(),
          optional(:label) => String.t() | nil,
          optional(:bounds) => bounds_map() | nil,
          optional(:source) => String.t() | nil
        }

  @type hash_input :: DebuggerTypes.wire_string_map() | [String.t()]

  @type timeline_event :: DebuggerTypes.runtime_event() | DebuggerTypes.debugger_event()
  @type events :: [timeline_event()]

  @type replay_count_map :: DebuggerTypes.replay_count_map()
  @type replay_telemetry :: DebuggerTypes.replay_telemetry()
  @type replay_preview_row_wire :: replay_preview_row() | wire_map()
  @type replay_preview_opts :: %{
          optional(:count) => wire_input(),
          optional(:target) => wire_input(),
          optional(:cursor_seq) => maybe_non_neg_integer(),
          optional(String.t()) => wire_input()
        }
  @type replay_target_filter :: replay_surface_target() | nil

  @type replay_metadata :: DebuggerTypes.replay_metadata()

  @type diagnostics_preview_source ::
          String.t()

  @type diagnostics_preview_result :: %{
          required(:source) => diagnostics_preview_source(),
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
          optional(:id) => String.t() | nil,
          optional(:label) => String.t() | nil,
          optional(:trigger) => String.t() | nil,
          optional(:trigger_display) => String.t() | nil,
          optional(:target) => String.t() | nil,
          optional(:message) => String.t() | nil,
          optional(:source) => String.t() | nil,
          optional(:button) => wire_value(),
          optional(:button_event) => wire_value(),
          optional(:interval_ms) => wire_value(),
          optional(:declared_interval_ms) => wire_value(),
          optional(:model_active?) => boolean(),
          optional(:injection_supported?) => boolean()
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
  @type json_export_input ::
          DebuggerTypes.wire_string_map() | view_tree() | [wire_value()] | wire_value()
  @type module_exposing :: String.t() | [String.t()]

  @type debugger_state_export_ctx :: %{
          optional(:format_version) => String.t(),
          required(:project_name) => String.t(),
          required(:project_slug) => String.t(),
          required(:timeline_mode) => String.t(),
          required(:timeline_text) => String.t(),
          required(:watch_model_json) => String.t(),
          required(:companion_model_json) => String.t(),
          required(:rendered_view_json) => String.t(),
          optional(:session_running) => boolean() | nil,
          optional(:session_event_count) => non_neg_integer() | nil,
          optional(:debugger_cursor_seq) => non_neg_integer() | String.t() | nil,
          optional(:selected_timeline_seq) => non_neg_integer() | String.t() | nil,
          optional(:watch_profile_id) => String.t() | nil,
          optional(:runtime_model_warnings) => String.t() | nil
        }

  @type debugger_state_map :: DebuggerTypes.runtime_state()
  @type wire_payload :: DebuggerTypes.debugger_timeline_payload()
end
