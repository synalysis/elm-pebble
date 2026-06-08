defmodule Ide.Mcp.ToolTypes do
  @moduledoc """
  MCP tool argument and result types; aliases domain types from Projects and Debugger.
  """

  alias Ide.AppStore.Types, as: AppStoreTypes
  alias Ide.Debugger.Types, as: DebuggerTypes
  alias Ide.Mcp.WireTypes
  alias Ide.Projects.Types, as: ProjectsTypes
  alias Ide.WatchModels

  @type json_value :: WireTypes.json_value()
  @type file_mtime :: :calendar.datetime()

  @type tool_result :: {:ok, map()} | {:error, String.t()}
  @type tool_persist_error :: atom() | String.t() | Ecto.Changeset.t() | map()
  @type tool_args :: map()

  @type release_defaults :: ProjectsTypes.release_defaults()
  @type debugger_settings :: ProjectsTypes.debugger_settings()
  @type github_config :: ProjectsTypes.github_config()
  @type compile_ingest_attrs :: DebuggerTypes.compile_ingest_attrs()
  @type publish_opts :: AppStoreTypes.publish_opts()
  @type debugger_runtime_state :: DebuggerTypes.runtime_state()
  @type debugger_screen :: WatchModels.wire_screen()

  @type render_tree_result :: %{
          required(:slug) => String.t(),
          required(:target) => String.t(),
          required(:screen) => debugger_screen(),
          required(:root_type) => String.t(),
          required(:node_count) => non_neg_integer(),
          required(:nodes) => [map()],
          optional(:tree) => DebuggerTypes.rendered_tree()
        }

  @type files_patch_result :: %{
          required(:slug) => String.t(),
          required(:source_root) => String.t(),
          required(:rel_path) => String.t(),
          required(:saved) => true,
          required(:old_sha256) => String.t(),
          required(:new_sha256) => String.t()
        }

  @type compiler_manifest_result :: %{
          required(:slug) => String.t(),
          required(:status) => :ok | :error,
          required(:manifest_path) => String.t(),
          required(:revision) => String.t(),
          required(:cached) => boolean(),
          required(:strict) => boolean(),
          required(:manifest) => map() | nil,
          required(:diagnostics) => [map()],
          required(:error_count) => non_neg_integer(),
          required(:warning_count) => non_neg_integer(),
          required(:output) => String.t()
        }

  @type projects_tree_result :: %{
          required(:slug) => String.t(),
          required(:tree) => ProjectsTypes.source_tree()
        }

  @type projects_settings_result :: %{
          optional(atom()) => json_value(),
          optional(String.t()) => json_value()
        }

  @type build_status_result :: %{
          optional(:slug) => String.t(),
          optional(:status) => String.t(),
          optional(:detail) => String.t(),
          optional(String.t()) => json_value()
        }

  @type ingest_compile_result :: {:ok, map()} | {:error, String.t()}

  @type files_read_result :: %{
          required(:slug) => String.t(),
          required(:source_root) => String.t(),
          required(:rel_path) => String.t(),
          required(:content) => binary()
        }

  @type files_write_result :: %{
          required(:slug) => String.t(),
          required(:source_root) => String.t(),
          required(:rel_path) => String.t(),
          required(:saved) => true
        }

  @type compiler_compile_result :: %{
          required(:slug) => String.t(),
          required(:status) => :ok | :error,
          required(:compiled_path) => String.t(),
          required(:revision) => String.t(),
          required(:cached) => boolean(),
          required(:diagnostics) => [map()],
          required(:error_count) => non_neg_integer(),
          required(:warning_count) => non_neg_integer(),
          required(:output) => String.t()
        }

  @type publish_validate_result :: %{
          required(:slug) => String.t(),
          required(:status) => :ok | :error,
          optional(:artifact_path) => String.t(),
          optional(:app_root) => String.t(),
          optional(atom()) => json_value(),
          optional(String.t()) => json_value()
        }

  @type debugger_state_replay_result :: %{
          required(:slug) => String.t(),
          required(:event_window) => non_neg_integer(),
          required(:runtime_fingerprint_digest) => DebuggerTypes.wire_map(),
          required(:snapshot_refs) => [DebuggerTypes.trace_snapshot_reference_row()],
          optional(atom()) => json_value(),
          optional(String.t()) => json_value()
        }

  @type debugger_state_full_result :: %{
          required(:slug) => String.t(),
          required(:state) => debugger_runtime_state(),
          required(:runtime_fingerprints) => DebuggerTypes.wire_map(),
          required(:runtime_fingerprint_digest) => DebuggerTypes.wire_map(),
          required(:snapshot_refs) => [DebuggerTypes.trace_snapshot_reference_row()],
          optional(atom()) => json_value(),
          optional(String.t()) => json_value()
        }

  @type debugger_state_result :: debugger_state_replay_result() | debugger_state_full_result()

  @type compiler_status_result :: %{
          required(:slug) => String.t(),
          required(:status) => :ok | :error,
          optional(:detail) => String.t(),
          optional(:diagnostics) => [map()],
          optional(String.t()) => json_value()
        }

  @type publish_prepare_result :: %{
          required(:slug) => String.t(),
          required(:status) => :ok | :error,
          optional(:artifact_path) => String.t(),
          optional(atom()) => json_value(),
          optional(String.t()) => json_value()
        }

  @type publish_submit_result :: %{
          required(:slug) => String.t(),
          required(:status) => :ok | :error,
          optional(:output) => String.t(),
          optional(:command) => String.t(),
          optional(:exit_code) => integer(),
          optional(:cwd) => String.t(),
          optional(String.t()) => json_value()
        }

  @type project_summary :: %{
          required(:name) => String.t(),
          required(:slug) => String.t(),
          required(:target_type) => String.t(),
          required(:source_roots) => [String.t()],
          required(:active) => boolean()
        }

  @type project_create_result :: project_summary()

  @type projects_list_result :: %{required(:projects) => [project_summary()]}

  @type project_graph_entry :: %{
          required(:name) => String.t(),
          required(:slug) => String.t(),
          required(:target_type) => String.t(),
          required(:active) => boolean(),
          required(:source_roots) => [String.t()],
          required(:workspace_path) => String.t(),
          required(:file_count) => non_neg_integer()
        }

  @type projects_graph_result :: %{required(:projects) => [project_graph_entry()]}

  @type audit_recent_result :: %{
          required(:entries) => [map()],
          required(:limit) => pos_integer(),
          required(:since) => String.t() | nil
        }

  @type debugger_render_tree_summary :: %{
          optional(:root_type) => String.t(),
          optional(:node_count) => non_neg_integer(),
          optional(:nodes) => [map()],
          optional(atom()) => json_value()
        }

  @type debugger_surface_state_result :: %{
          required(:slug) => String.t(),
          required(:seq) => non_neg_integer(),
          required(:target) => String.t(),
          required(:screen) => debugger_screen(),
          required(:model) => debugger_surface_model_entry(),
          optional(:last_message) => String.t() | nil,
          optional(:protocol_messages) => list(),
          optional(:runtime_fingerprint) => DebuggerTypes.wire_map() | nil,
          optional(:render_tree) => debugger_render_tree_summary() | nil,
          optional(atom()) => json_value()
        }

  @type compiler_recent_result :: %{
          required(:entries) => [map()],
          required(:limit) => pos_integer(),
          optional(:slug) => String.t() | nil,
          required(:since) => String.t() | nil
        }

  @type debugger_surface_model_entry :: %{
          required(:target) => String.t(),
          required(:model) => DebuggerTypes.wire_map(),
          required(:runtime_model) => DebuggerTypes.wire_map(),
          required(:model_keys) => [String.t()],
          required(:runtime_model_keys) => [String.t()],
          optional(atom()) => json_value(),
          optional(String.t()) => json_value()
        }

  @type debugger_models_result :: %{
          required(:slug) => String.t(),
          required(:seq) => non_neg_integer(),
          required(:running) => boolean(),
          required(:revision) => String.t() | nil,
          required(:watch_profile_id) => String.t(),
          required(:models) => %{optional(atom()) => debugger_surface_model_entry()}
        }

  @type compiler_check_result :: %{
          required(:slug) => String.t(),
          required(:status) => :ok | :error,
          required(:checked_path) => String.t(),
          required(:diagnostics) => [map()],
          required(:error_count) => non_neg_integer(),
          required(:warning_count) => non_neg_integer(),
          required(:output) => String.t(),
          optional(:source_root) => String.t()
        }

  @type pebble_package_result :: %{
          required(:slug) => String.t(),
          required(:status) => :ok | :error,
          required(:artifact_path) => String.t(),
          optional(:package_path) => String.t(),
          required(:app_root) => String.t(),
          required(:build_result) => map()
        }

  @type debugger_timeline_event :: %{
          optional(atom()) => json_value(),
          optional(String.t()) => json_value()
        }

  @type debugger_timeline_result :: %{
          required(:slug) => String.t(),
          required(:seq) => non_neg_integer(),
          required(:count) => non_neg_integer(),
          required(:timeline) => [debugger_timeline_event()]
        }

  @type debugger_simulator_settings_result :: %{
          required(:slug) => String.t(),
          required(:settings) => DebuggerTypes.simulator_settings(),
          required(:persisted_settings) => DebuggerTypes.simulator_settings()
        }

  @type slug_ok_result :: %{required(:slug) => String.t(), required(:deleted) => true}

  @type compiler_cached_result :: %{
          required(:slug) => String.t(),
          required(:cached) => true,
          required(:at) => String.t(),
          required(:result) => map(),
          optional(:revision) => String.t()
        }

  @type tool_payload_value :: json_value() | map() | [map()]

  @type debugger_preview_diagnostics_result :: %{
          required(:slug) => String.t(),
          required(:target) => String.t(),
          required(:status) => String.t(),
          required(:render_source) => String.t(),
          required(:node_count) => non_neg_integer(),
          optional(atom()) => tool_payload_value(),
          optional(String.t()) => tool_payload_value()
        }

  @type traces_summary_result :: %{
          optional(:trace_id) => String.t() | nil,
          optional(:slug) => String.t() | nil,
          required(:since) => String.t() | nil,
          required(:window) => map(),
          required(:latest_status) => map(),
          required(:actions) => [map()]
        }

  @type sessions_recent_activity_result :: %{
          required(:projects) => [map()],
          required(:limit) => pos_integer(),
          optional(:slug) => String.t() | nil,
          required(:since) => String.t() | nil
        }

  @type debugger_cursor_inspect_replay_result :: %{
          required(:slug) => String.t(),
          required(:cursor_seq) => non_neg_integer() | nil,
          required(:event_window) => non_neg_integer(),
          required(:snapshot_refs) => [map()],
          optional(atom()) => tool_payload_value(),
          optional(String.t()) => tool_payload_value()
        }

  @type debugger_cursor_inspect_full_result :: %{
          required(:slug) => String.t(),
          required(:cursor_seq) => non_neg_integer() | nil,
          required(:event_window) => non_neg_integer(),
          required(:snapshot_refs) => [map()],
          required(:elmc_diagnostics) => [map()],
          required(:runtime_fingerprint_digest) => map(),
          optional(atom()) => tool_payload_value(),
          optional(String.t()) => tool_payload_value()
        }

  @type debugger_cursor_inspect_result ::
          debugger_cursor_inspect_replay_result() | debugger_cursor_inspect_full_result()

  @type traces_export_result :: %{
          optional(:trace_id) => String.t() | nil,
          optional(:slug) => String.t() | nil,
          required(:since) => String.t() | nil,
          required(:limit) => pos_integer(),
          required(:export_sha256) => String.t(),
          required(:export_json) => String.t()
        }

  @type sessions_summary_entry :: %{
          required(:slug) => String.t(),
          required(:active) => boolean(),
          required(:target_type) => String.t(),
          optional(:latest_check_status) => :ok | :error | String.t() | nil,
          optional(:latest_compile_status) => :ok | :error | String.t() | nil,
          optional(:latest_manifest_status) => :ok | :error | String.t() | nil,
          optional(:latest_manifest_strict) => boolean() | nil,
          required(:checks_count) => non_neg_integer(),
          required(:compiles_count) => non_neg_integer(),
          required(:manifests_count) => non_neg_integer(),
          required(:actions_count) => non_neg_integer(),
          required(:screenshots_count) => non_neg_integer()
        }

  @type sessions_summary_result :: %{
          required(:projects) => [sessions_summary_entry()],
          optional(:slug) => String.t() | nil,
          required(:since) => String.t() | nil
        }

  @type debugger_configuration_result :: %{
          required(:slug) => String.t(),
          required(:values) => DebuggerTypes.companion_configuration_values(),
          required(:configuration) => DebuggerTypes.companion_configuration()
        }

  @type trace_export_file_entry :: %{
          required(:file_name) => String.t(),
          required(:path) => String.t(),
          required(:bytes) => non_neg_integer(),
          required(:modified_at) => String.t() | nil
        }

  @type trace_export_file_internal :: %{
          required(:file_name) => String.t(),
          required(:path) => String.t(),
          required(:bytes) => non_neg_integer(),
          required(:modified_at) => String.t(),
          required(:sort_key) => file_mtime()
        }

  @type trace_exports_summary :: %{
          required(:total_count) => non_neg_integer(),
          required(:total_bytes) => non_neg_integer(),
          required(:newest_modified_at) => String.t() | nil,
          required(:oldest_modified_at) => String.t() | nil
        }

  @type trace_health_thresholds :: %{
          required(:warn_count) => pos_integer(),
          required(:warn_bytes) => pos_integer()
        }

  @type trace_bundle_compiler_context :: %{
          required(:latest) => map(),
          required(:recent) => map()
        }

  @type trace_bundle :: %{
          optional(:trace_id) => String.t() | nil,
          optional(:slug) => String.t() | nil,
          required(:limit) => pos_integer(),
          required(:since) => String.t() | nil,
          required(:audit_entries) => [map()],
          required(:compiler_context) => trace_bundle_compiler_context()
        }

  @type traces_exports_list_result :: %{
          required(:entries) => [trace_export_file_entry()],
          required(:limit) => pos_integer(),
          required(:total_available) => non_neg_integer()
        }

  @type trace_health_status_result :: %{
          required(:status) => String.t(),
          required(:recommendation) => String.t(),
          required(:trace_exports) => trace_exports_summary(),
          required(:thresholds) => trace_health_thresholds(),
          required(:suggested_keep_latest) => non_neg_integer()
        }

  @type policy_validation_result :: %{
          required(:status) => String.t(),
          required(:findings) => [map()]
        }

  @type sessions_trace_health_result :: %{
          required(:status) => String.t(),
          required(:recommendation) => String.t(),
          required(:trace_exports) => trace_exports_summary(),
          required(:thresholds) => trace_health_thresholds(),
          required(:suggested_keep_latest) => non_neg_integer(),
          required(:policy_validation) => policy_validation_result()
        }

  @type debugger_auto_fire_result :: %{
          required(:slug) => String.t(),
          required(:auto_fire) => DebuggerTypes.wire_map(),
          required(:auto_fire_subscriptions) => [DebuggerTypes.wire_map()],
          required(:runtime_auto_tick) => DebuggerTypes.auto_tick()
        }

  @type debugger_disabled_subscriptions_result :: %{
          required(:slug) => String.t(),
          required(:disabled_subscriptions) => list(),
          required(:runtime_disabled_subscriptions) => list()
        }

  @type debugger_slug_state_result :: %{
          required(:slug) => String.t(),
          required(:state) => debugger_runtime_state()
        }

  @type traces_policy_configured_settings :: %{
          optional(:warn_count) => pos_integer() | nil,
          optional(:warn_bytes) => pos_integer() | nil,
          optional(:keep_latest) => non_neg_integer() | nil,
          optional(:target_keep_latest) => non_neg_integer() | nil
        }

  @type traces_policy_effective_settings :: %{
          required(:warn_count) => pos_integer(),
          required(:warn_bytes) => pos_integer(),
          required(:keep_latest) => non_neg_integer(),
          required(:target_keep_latest) => non_neg_integer()
        }

  @type traces_policy_result :: %{
          required(:configured) => traces_policy_configured_settings(),
          required(:effective) => traces_policy_effective_settings()
        }

  @type traces_policy_validate_result :: %{
          required(:status) => String.t(),
          required(:policy) => traces_policy_effective_settings(),
          required(:findings) => [map()]
        }

  @type packages_module_docs_result :: %{
          required(:package) => String.t(),
          required(:version) => String.t(),
          required(:module) => String.t(),
          required(:markdown) => String.t()
        }

  @type debugger_watch_profiles_result :: %{required(:watch_profiles) => list()}

  @type debugger_simulator_settings_state_result :: %{
          required(:slug) => String.t(),
          required(:settings) => DebuggerTypes.simulator_settings(),
          required(:state) => debugger_runtime_state()
        }

  @type debugger_configuration_values_state_result :: %{
          required(:slug) => String.t(),
          required(:values) => DebuggerTypes.companion_configuration_values(),
          required(:state) => debugger_runtime_state()
        }

  @type debugger_auto_fire_settings_state_result :: %{
          required(:slug) => String.t(),
          required(:auto_fire) => DebuggerTypes.wire_map(),
          required(:auto_fire_subscriptions) => [DebuggerTypes.wire_map()],
          required(:state) => debugger_runtime_state()
        }

  @type debugger_disabled_subscriptions_state_result :: %{
          required(:slug) => String.t(),
          required(:disabled_subscriptions) => [DebuggerTypes.disabled_subscription()],
          required(:state) => debugger_runtime_state()
        }

  @type debugger_export_trace_result :: %{
          required(:slug) => String.t(),
          required(:export_json) => String.t(),
          required(:sha256) => String.t(),
          required(:byte_size) => non_neg_integer()
        }

  @type traces_export_write_result :: %{
          optional(:trace_id) => String.t() | nil,
          optional(:slug) => String.t() | nil,
          required(:export_sha256) => String.t(),
          required(:bytes) => non_neg_integer(),
          required(:path) => String.t(),
          required(:file_name) => String.t()
        }

  @type traces_exports_prune_result :: %{
          required(:keep_latest) => pos_integer(),
          required(:deleted_count) => non_neg_integer(),
          required(:deleted_files) => [String.t()],
          required(:remaining_count) => non_neg_integer()
        }

  @type traces_maintenance_prune_skipped :: %{
          required(:deleted_count) => 0,
          required(:deleted_files) => [],
          required(:remaining_count) => non_neg_integer()
        }

  @type traces_maintenance_result :: %{
          required(:mode) => String.t(),
          required(:status) => String.t(),
          required(:policy_validation) => policy_validation_result(),
          required(:health_before) => trace_health_status_result(),
          required(:health_after) => trace_health_status_result(),
          required(:thresholds) => %{
            required(:warn_count) => pos_integer(),
            required(:warn_bytes) => pos_integer()
          },
          required(:target_keep_latest) => pos_integer(),
          required(:prune) => traces_exports_prune_result() | traces_maintenance_prune_skipped()
        }

  @type pebble_install_result :: %{
          required(:slug) => String.t(),
          required(:artifact_path) => String.t(),
          required(:install_result) => map()
        }

  @type screenshot_entry :: %{
          required(:filename) => String.t() | nil,
          required(:target_device) => String.t() | nil,
          required(:emulator_target) => String.t() | nil,
          required(:captured_at) => String.t() | nil,
          required(:timestamp) => String.t() | nil,
          required(:mime_type) => String.t(),
          required(:url) => String.t() | nil,
          required(:absolute_path) => String.t() | nil
        }

  @type screenshots_list_result :: %{
          required(:slug) => String.t(),
          required(:count) => non_neg_integer(),
          required(:screenshots) => [screenshot_entry()]
        }

  @type screenshots_read_result :: %{
          required(:slug) => String.t(),
          required(:screenshot) => screenshot_entry(),
          required(:mime_type) => String.t(),
          required(:encoding) => String.t(),
          required(:bytes) => non_neg_integer(),
          required(:sha256) => String.t(),
          required(:content_base64) => String.t()
        }

  @type screenshots_capture_result :: %{
          required(:slug) => String.t(),
          required(:screenshot) => map() | nil,
          required(:output) => String.t(),
          required(:exit_code) => integer(),
          required(:command) => String.t(),
          required(:cwd) => String.t()
        }
end
