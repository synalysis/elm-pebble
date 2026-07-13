defmodule Ide.Debugger.Types do
  @moduledoc """
  Shared types for debugger runtime state, timeline rows, and compiler ingest payloads.
  """

  alias ElmEx.CoreIR.Types, as: CoreIRTypes
  alias ElmEx.DebuggerContract.Payload
  alias Ide.CompanionProtocol.WireSchema
  alias Ide.Debugger.Protocol.{ConstructorValue, Event, Schema}
  alias Ide.Debugger.RuntimeArtifacts.Types, as: RuntimeArtifactsTypes

  alias Ide.Debugger.Types.{
    ProtocolTxRxPayload,
    CompanionConfiguration,
    RuntimeFollowupRow,
    SourceLocation,
    HttpSimulatedResponse,
    AppModel,
    ActiveSubscription,
    AvailableTriggersAttrs,
    AutoTick,
    CmdCall,
    CompanionBridgeRequest,
    CompanionSubscriptionFieldDef,
    CompileIngestAttrs,
    CompileIngestBridge,
    ElmcCliIngestBridge,
    StepExecutionContract,
    DebuggerTimelineRow,
    DeviceRequest,
    DisabledSubscription,
    DebuggerContractEventPayload,
    ElmcDiagnosticPreview,
    ElmcEventPayload,
    ElmcSurfaceFields,
    HotReloadEventPayload,
    MessageInEventPayload,
    PackageCmdEventPayload,
    PackageCmdErrorEventPayload,
    PendingHttpFollowupItem,
    PendingProtocolDeliveryItem,
    ImportTraceBody,
    TraceExportWire,
    RuntimeFingerprint,
    ElmxManifest,
    CompanionInjectionForm,
    AutoFireClock,
    DevicePreview,
    ExecutionModel,
    ExecutionRuntimeSnapshot,
    ExportTraceOpts,
    ExportTraceResult,
    InnerRuntimeModel,
    InjectTriggerAttrs,
    LaunchContext,
    ProtocolTxRxPayload,
    ReplayAttrs,
    ReplayEventPayload,
    ReplayRow,
    RuntimeExecEventPayload,
    RuntimeStatusEventPayload,
    ReloadAttrs,
    SaveConfigurationAttrs,
    RuntimeEventPayload,
    SessionAttrs,
    SimulatorSubscriptionPayload,
    SnapshotContinueAttrs,
    SpeakerCommand,
    SpeakerEffect,
    StepAttrs,
    RuntimeState,
    RuntimeStepResult,
    Shell,
    SimulatorSettings,
    SnapshotOpts,
    SubscriptionRow,
    TrackedHttpCommand,
    TriggerCandidate,
    WatchProfile
  }

  @type core_ir :: CoreIRTypes.wire_core_ir() | nil
  @type core_ir_expr :: CoreIRTypes.expr() | CoreIRTypes.Expr.wire_expr()
  @type introspect_snapshot :: Payload.snapshot()

  @type launch_context :: LaunchContext.t() | LaunchContext.wire_map()

  @type runtime_state :: RuntimeState.t() | RuntimeState.wire_map()

  @type runtime_event :: RuntimeState.runtime_event()

  @type debugger_event :: RuntimeState.debugger_event()

  @type simulator_settings :: SimulatorSettings.t() | SimulatorSettings.wire_map()

  @type watch_profile :: WatchProfile.profile() | WatchProfile.wire_profile()

  @type watch_profile_list_item :: WatchProfile.list_item() | WatchProfile.wire_list_item()

  @type watch_profiles_map :: %{optional(String.t()) => watch_profile()}

  @type timeline_row :: DebuggerTimelineRow.t()

  @type subscription_row :: SubscriptionRow.t() | SubscriptionRow.wire_map()

  @type trigger_candidate :: TriggerCandidate.t() | TriggerCandidate.wire_map()

  @type event_payload :: RuntimeEventPayload.t()

  @type session_attrs :: SessionAttrs.t() | SessionAttrs.wire_map()

  @type reload_attrs :: ReloadAttrs.t() | ReloadAttrs.wire_map()

  @type step_attrs :: StepAttrs.t() | StepAttrs.wire_map()

  @type inject_trigger_attrs :: InjectTriggerAttrs.t() | InjectTriggerAttrs.wire_map()

  @type available_triggers_attrs :: AvailableTriggersAttrs.t() | AvailableTriggersAttrs.wire_map()

  @type replay_attrs :: ReplayAttrs.t() | ReplayAttrs.wire_map()

  @type snapshot_continue_attrs :: SnapshotContinueAttrs.t() | SnapshotContinueAttrs.wire_map()

  @type protocol_tx_rx_payload :: ProtocolTxRxPayload.t() | ProtocolTxRxPayload.wire_map()

  @type replay_row :: ReplayRow.t() | ReplayRow.wire_map()

  @type replay_metadata :: ReplayEventPayload.metadata()

  @type replay_preview_row :: ReplayEventPayload.replay_preview_row()

  @type replay_telemetry :: ReplayEventPayload.replay_telemetry()

  @type replay_count_map :: ReplayEventPayload.count_map()

  @type save_configuration_attrs :: SaveConfigurationAttrs.t() | SaveConfigurationAttrs.wire_map()

  @type import_trace_input :: ImportTraceBody.input()

  @type import_trace_body :: ImportTraceBody.t() | ImportTraceBody.wire_map()

  @type trace_export_event_row :: TraceExportWire.export_event_row() | TraceExportWire.wire_row()

  @type trace_export_snapshot_refs :: TraceExportWire.snapshot_refs()

  @type trace_snapshot_reference_row :: TraceExportWire.snapshot_reference_row()

  @type debugger_contract_event_payload ::
          DebuggerContractEventPayload.t() | DebuggerContractEventPayload.wire_map()

  @type elm_introspect_event_payload :: debugger_contract_event_payload()

  @type hot_reload_event_payload :: HotReloadEventPayload.t() | HotReloadEventPayload.wire_map()

  @type runtime_exec_event_payload ::
          RuntimeExecEventPayload.t() | RuntimeExecEventPayload.wire_map()

  @type runtime_status_event_payload ::
          RuntimeStatusEventPayload.t() | RuntimeStatusEventPayload.wire_map()

  @type message_in_event_payload :: MessageInEventPayload.t() | MessageInEventPayload.wire_map()

  @type package_cmd_event_payload ::
          PackageCmdEventPayload.t() | PackageCmdEventPayload.wire_map()

  @type package_cmd_error_event_payload ::
          PackageCmdErrorEventPayload.t() | PackageCmdErrorEventPayload.wire_map()

  @type runtime_event_kind :: RuntimeEventPayload.event_kind()

  @type snapshot_opt :: SnapshotOpts.opt()

  @type snapshot_opts :: SnapshotOpts.opts()

  @type export_trace_opt :: ExportTraceOpts.opt()

  @type export_trace_opts :: ExportTraceOpts.opts()

  @type export_trace_result :: ExportTraceResult.t()

  @type execution_runtime_snapshot ::
          ExecutionRuntimeSnapshot.t() | ExecutionRuntimeSnapshot.wire_map()

  @type compile_ingest_attrs :: CompileIngestAttrs.t() | CompileIngestAttrs.wire_map()

  @type emulator_rc_fail_attrs :: %{
          optional(:code) => non_neg_integer() | String.t() | nil,
          optional(:line) => non_neg_integer() | String.t() | nil,
          optional(String.t()) => non_neg_integer() | String.t() | nil
        }

  @type step_executor_request :: StepExecutionContract.executor_request()

  @type step_executor_result :: StepExecutionContract.executor_result()

  @type elmc_cli_project_run :: Elmc.CLI.Types.project_run()

  @type elmc_cli_manifest_run :: Elmc.CLI.Types.manifest_run()

  @type elmc_cli_ingest_opts :: ElmcCliIngestBridge.ingest_opts()

  @type runtime_event_wire :: String.t()

  @type compiler_check_result :: CompileIngestBridge.check_result()

  @type compiler_compile_result :: CompileIngestBridge.compile_result()

  @type compiler_manifest_result :: CompileIngestBridge.manifest_result()

  @type elmc_event_payload :: ElmcEventPayload.t()

  @type elmc_surface_fields :: ElmcSurfaceFields.wire_map()

  @type cmd_call :: CmdCall.t() | CmdCall.wire_map()

  @type elmc_diagnostic_preview :: ElmcDiagnosticPreview.preview()

  @type elmc_diagnostic_row :: ElmcDiagnosticPreview.row() | ElmcDiagnosticPreview.wire_row()

  @type auto_tick :: AutoTick.t() | AutoTick.wire_map()

  @type disabled_subscription :: DisabledSubscription.t() | DisabledSubscription.wire_map()

  @type companion_bridge_request ::
          CompanionBridgeRequest.t() | CompanionBridgeRequest.wire_map()

  @type tracked_http_command :: TrackedHttpCommand.t() | TrackedHttpCommand.wire_map()

  @type protocol_event :: Event.t()

  @type device_request :: DeviceRequest.t() | DeviceRequest.wire_map()

  @type device_data_request :: device_request()

  @type protocol_schema :: Schema.t() | Schema.wire_schema()

  @type protocol_field :: Schema.field()

  @type protocol_error_atom ::
          :invalid_trace
          | :invalid_json
          | :slug_mismatch
          | :missing_project_protocol
          | :repo_unavailable
          | :invalid_http_command

  @type protocol_error ::
          protocol_error_atom()
          | String.t()
          | {:bad_body, String.t()}

  @type protocol_wire_type :: Schema.wire_type()

  @type protocol_wire_slot :: Schema.wire_slot()

  @type protocol_key_ids :: WireSchema.key_ids()

  @type protocol_ctor_value :: ConstructorValue.t() | ConstructorValue.wire_value()

  @type protocol_schema_message :: Schema.message() | Schema.runtime_message()

  @type protocol_message_wire_value ::
          protocol_ctor_value() | wire_string_map() | String.t() | nil

  @type protocol_wire_scalar :: String.t() | integer() | float() | boolean()

  @type protocol_tag_tuple :: {atom() | String.t(), [protocol_wire_arg()]}

  @type protocol_wire_arg ::
          protocol_ctor_value()
          | protocol_wire_scalar()
          | protocol_tag_tuple()
          | wire_string_map()
          | nil

  @type protocol_wire_normalize_input :: protocol_wire_arg()

  @type init_model_values :: wire_string_map()

  @type debugger_contract :: Payload.wire_payload()

  @type elm_introspect :: debugger_contract()

  @type elmx_manifest :: ElmxManifest.t() | ElmxManifest.wire_map()

  @type inner_runtime_model :: InnerRuntimeModel.t() | InnerRuntimeModel.wire_map()

  @type app_model :: AppModel.t() | AppModel.wire_map()

  @type shell :: Shell.t() | Shell.wire_map()

  @type execution_model :: ExecutionModel.t() | ExecutionModel.wire_map()

  @type protocol_message :: protocol_ctor_value()

  @type runtime_model :: execution_model()

  @type surface_target :: :watch | :companion | :phone

  @type surface_label_input :: surface_target() | String.t() | atom() | nil

  @type wire_scalar :: String.t() | integer() | float() | boolean() | nil

  @type wire_input :: Elmx.Types.wire_input()

  @typedoc "String-keyed wire map (JSON export, protocol payloads, corpus snapshots)."
  @type wire_string_map :: %{optional(String.t()) => wire_input()}

  @typedoc "Companion environment snapshot (`sun`, `moon`, `tide` wire unions)."
  @type environment_info_map :: %{
          optional(String.t()) => wire_input()
        }

  @typedoc """
  Generic debugger wire map for runtime payloads with mixed atom/string keys.
  Prefer `wire_string_map/0` or closed row types when the shape is known.
  """
  @type wire_map :: %{optional(String.t()) => wire_input(), optional(atom()) => wire_input()}

  @type companion_bridge_payload ::
          boolean()
          | wire_string_map()
          | [wire_string_map()]
          | String.t()
          | integer()
          | nil

  @type companion_callback_result ::
          {:ok, companion_bridge_payload()} | {:error, String.t()}

  @type companion_connectivity_callback_result ::
          {:ok, true}
          | {:ok, false}
          | {:ok, companion_bridge_payload()}
          | {:error, String.t()}

  @type companion_subscription_field_def :: CompanionSubscriptionFieldDef.t()

  @type companion_subscription_contract :: %{
          required(:source) => String.t(),
          required(:target_suffixes) => [String.t()],
          required(:payload) => atom(),
          optional(:trigger_slugs) => [String.t()],
          optional(:fields) => [companion_subscription_field_def()],
          optional(:plain_result) => boolean(),
          optional(:ok_result_variant) => String.t()
        }

  @type watch_subscription_contract :: %{
          required(:id) => atom(),
          required(:target_suffixes) => [String.t()],
          optional(:simulator_arg_types) => %{String.t() => String.t()}
        }

  @type speaker_command :: SpeakerCommand.t() | SpeakerCommand.wire_map()

  @type speaker_effect :: SpeakerEffect.t() | SpeakerEffect.wire_map()

  @type active_subscription :: ActiveSubscription.t() | ActiveSubscription.wire_map()

  @type simulator_compass_heading ::
          SimulatorSubscriptionPayload.compass_heading()

  @type simulator_screen_payload :: SimulatorSubscriptionPayload.screen()

  @type simulator_rect_payload :: SimulatorSubscriptionPayload.rect()

  @type companion_injection_form_data :: CompanionInjectionForm.t()

  @type companion_injection_field_entry :: CompanionInjectionForm.companion_field_entry()

  @type pending_protocol_delivery_item ::
          PendingProtocolDeliveryItem.t() | PendingProtocolDeliveryItem.wire_item()

  @type pending_http_followup_item ::
          PendingHttpFollowupItem.t() | PendingHttpFollowupItem.wire_item()

  @type companion_subscription_source :: %{
          optional(:source) => String.t(),
          optional(:plain_result) => boolean(),
          optional(:ok_result_variant) => String.t()
        }

  @type protocol_metadata_value :: wire_scalar() | wire_string_map() | nil

  @type phone_to_watch_message_value :: protocol_ctor_value() | wire_string_map()

  @type phone_to_watch_payload :: subscription_payload() | boolean() | String.t()

  @type elmc_wire_ctor_call :: wire_ctor()

  @type elmc_wire_ctor_value :: wire_ctor()

  @type simulator_command_input ::
          elmc_wire_ctor_value() | elmc_wire_ctor_call() | wire_scalar() | wire_string_map()

  @type subscription_row_input :: DisabledSubscription.wire_map()

  @type runtime_model_patch :: wire_string_map()

  @type timeline_step_message_value :: subscription_payload() | wire_scalar() | nil

  @type debugger_timeline_payload :: event_payload()

  @typedoc "MCP/export compact timeline event payload (`target`, `message`, `status`, etc.)."
  @type compact_timeline_event_payload :: %{
          optional(String.t()) => wire_scalar() | nil
        }

  @type runtime_fingerprint_digest :: RuntimeFingerprint.digest_surfaces()

  @type mcp_fingerprint_compare_result :: RuntimeFingerprint.mcp_compare_result()

  @type auto_fire_clock :: AutoFireClock.t()

  @type auto_fire_clock_entry :: AutoFireClock.entry()

  @type current_date_time_preview :: DevicePreview.current_date_time()

  @type firmware_version_record :: DevicePreview.firmware_version()

  @type surface_fingerprints :: RuntimeFingerprint.surface_fingerprints()

  @type protocol_binding_record :: wire_string_map()

  @type preview_view_derivation :: %{
          required(:view_output) => runtime_view_nodes(),
          optional(:view_tree) => view_output_tree() | nil,
          optional(:preview_error) => String.t()
        }

  @type protocol_timeline_event :: ProtocolTxRxPayload.protocol_event()

  @type weather_info_map :: device_preview_map()

  @type companion_configuration :: CompanionConfiguration.wire_map()

  @type companion_configuration_values :: CompanionConfiguration.values()

  @type runtime_followup_row :: RuntimeFollowupRow.wire_row()

  @type source_location :: SourceLocation.wire_map()

  @type http_simulated_response :: HttpSimulatedResponse.wire_map()

  @type api_suffix_contract :: %{required(:target_suffixes) => [String.t()]}

  @type protocol_eval_context :: %{
          required(:message_value) => protocol_message_wire_value() | nil,
          required(:runtime_model) => inner_runtime_model(),
          required(:simulator_settings) => simulator_settings(),
          required(:protocol_ctor) => String.t() | nil,
          required(:arg_index) => non_neg_integer() | nil,
          required(:direction) => :watch_to_phone | :phone_to_watch,
          required(:schema) => Schema.t() | Schema.wire_schema() | nil,
          required(:message_fields) => [Schema.field()] | nil
        }

  @type resource_index_map :: %{optional(String.t()) => non_neg_integer()}

  @type http_eval_context :: %{
          optional(:module) => String.t() | nil,
          optional(:source_module) => String.t() | nil,
          optional(:vector_resource_indices) => resource_index_map(),
          optional(:bitmap_resource_indices) => resource_index_map(),
          optional(:animation_resource_indices) => resource_index_map(),
          optional(:simulator_weather) => device_preview_map() | wire_string_map()
        }

  @type eval_context :: protocol_eval_context() | http_eval_context()

  @type protocol_var_bindings :: wire_string_map()

  @type screen_dimension_patch :: %{
          optional(String.t()) => pos_integer()
        }

  @type device_preview_map :: %{
          optional(String.t()) => String.t() | integer() | boolean()
        }

  @type device_preview :: nil | boolean() | String.t() | device_preview_map()

  @type elm_maybe :: protocol_ctor_value() | wire_string_map() | nil

  @type protocol_inbound_row :: %{
          optional(String.t()) => String.t() | wire_string_map() | list() | nil
        }

  @type subscription_payload ::
          wire_string_map() | protocol_ctor_value() | wire_scalar() | [wire_input()]

  @type view_output_row :: Elmx.Types.view_output_row()

  @type view_output_scene_token ::
          {:text, wire_value(), integer(), integer()}
          | {:text_label, wire_value(), integer(), integer()}
          | {:text_int, wire_value(), integer(), integer()}
          | {:bitmap_in_rect, integer(), integer(), integer(), integer(), integer()}
          | {:rotated_bitmap, integer(), integer(), integer()}
          | {:bitmap_sequence_at, integer(), integer(), integer(), integer()}
          | {:vector_at, integer(), integer(), integer()}
          | {:vector_sequence_at, integer(), integer(), integer(), integer()}
          | {atom(), String.t()}

  @type view_output_node :: view_output_row() | Elmx.Types.view_output_tree()

  @type view_output_tree :: Elmx.Types.view_output_tree()

  @type elm_msg :: Elmx.Types.elm_msg()

  @type json_value :: Elmx.Types.json_value()

  @type runtime_protocol_event :: Elmx.Types.protocol_event()

  @type comparable :: Elmx.Types.comparable()

  @type wire_cmd :: Elmx.Types.wire_cmd()

  @type wire_value :: Elmx.Types.wire_value()

  @type elmx_executor_request :: Elmx.Types.executor_request()

  @type elmx_execution_payload :: Elmx.Types.execution_payload()

  @type elmx_view_preview_payload :: Elmx.Types.view_preview_payload()

  @type elmx_execution_error :: Elmx.Types.execution_error()

  @type elmx_runtime_model :: Elmx.Types.runtime_model()

  @type elm_dict :: Elmx.Types.elm_dict()

  @type elm_set :: Elmx.Types.elm_set()

  @type elm_array :: Elmx.Types.elm_array()

  @type elm_list :: Elmx.Types.elm_list()

  @type elm_char_list :: Elmx.Types.elm_char_list()

  @type ui_node :: Elmx.Types.ui_node()

  @type ui_point :: Elmx.Types.ui_point()

  @type ui_bounds :: Elmx.Types.ui_bounds()

  @type ui_color :: Elmx.Types.ui_color()

  @type ui_path :: Elmx.Types.ui_path()

  @type string_like :: Elmx.Types.string_like()

  @type launch_reason_like :: Elmx.Types.launch_reason_like()

  @type view_shape_input :: Elmx.Types.view_shape_input()

  @type render_op_input :: Elmx.Types.render_op_input()

  @type numeric_input :: Elmx.Types.numeric_input()

  @type maybe_like :: Elmx.Types.maybe_like()

  @type result_like :: Elmx.Types.result_like()

  @type json_object_pair :: Elmx.Types.json_object_pair()

  @type storage_value_input :: Elmx.Types.storage_value_input()

  @type elm_value :: Elmx.Types.elm_value()

  @type wire_cmd_input :: Elmx.Types.wire_cmd_input()

  @type data_log_tag :: Elmx.Types.data_log_tag()

  @type subscription_mask_item :: Elmx.Types.subscription_mask_item()

  @type display_shape_like :: Elmx.Types.display_shape_like()

  @type elm_hof :: Elmx.Types.elm_hof()

  @type color_mode_like :: Elmx.Types.color_mode_like()

  @type json_decoder_spec :: Elmx.Types.json_decoder_spec()

  @type json_primitive :: Elmx.Types.json_primitive()

  @type json_decoder :: Elmx.Types.json_decoder()

  @type compile_failure_detail :: Elmx.Types.compile_failure_detail()

  @type parse_error :: :parse_error | :entry_not_found | atom() | String.t()

  @type elm_tuple_like :: Elmx.Types.elm_tuple_like()

  @type dict_entry_input :: Elmx.Types.dict_entry_input()

  @type wire_ctor :: Elmx.Types.wire_ctor()

  @type elmx_wire_map :: Elmx.Types.wire_map()

  @type followup_row :: Elmx.Types.followup_row()

  @type frame_tick_payload :: Elmx.Types.frame_tick_payload()

  @type runtime_step_result :: RuntimeStepResult.t() | RuntimeStepResult.wire_result()

  @type replay_step_message :: ReplayRow.t()

  @type runtime_fingerprint :: RuntimeFingerprint.runtime_fingerprint()

  @type fingerprint_compare_result :: RuntimeFingerprint.fingerprint_compare_result()

  @type fingerprint_compare_surface_row :: RuntimeFingerprint.fingerprint_compare_surface_row()

  @type normalized_export_wire :: %{optional(String.t()) => normalized_export_term()}

  @type normalized_export_term ::
          wire_scalar() | normalized_export_wire() | [normalized_export_term()]

  @type static_task_result ::
          protocol_ctor_value() | {protocol_ctor_value(), protocol_ctor_value()}

  @type runtime_view_nodes :: [view_output_row()]

  @type auto_fire_candidate :: trigger_candidate()

  @type runtime_entrypoint :: {String.t(), String.t()}

  @type runtime_artifacts :: RuntimeArtifactsTypes.t()

  @type rendered_tree :: view_output_tree()

  @type simulator_setting_keys ::
          :platform_target
          | :timeline_limit
          | :auto_fire
          | :watch_profile_id
          | :geolocation
          | :companion_bridge

  @type execution_fallback_reason ::
          atom()
          | String.t()
          | module()
          | {:elmx_module_not_registered, String.t()}
          | {:external_executor_not_loaded, module()}
          | {:bad_body, String.t()}

  @type execution_error ::
          :invalid_execution_input
          | :invalid_http_command
          | {:core_ir_execution_failed, execution_fallback_reason()}
          | {:invalid_runtime_executor_result, execution_fallback_reason()}
          | {:elmc_runtime_executor_failed, execution_fallback_reason()}
          | {:invalid_elmc_runtime_result, execution_fallback_reason()}
          | {:elmc_runtime_unavailable, execution_fallback_reason()}
          | {:external_runtime_executor_failed, execution_fallback_reason()}
          | {:invalid_external_runtime_result, execution_fallback_reason()}
          | execution_fallback_reason()

  @type http_executor_error :: :invalid_http_command | protocol_error()

  @type param_list :: [String.t()]
end
