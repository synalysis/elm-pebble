defmodule Ide.Debugger.Types do
  @moduledoc """
  Shared types for debugger runtime state, timeline rows, and compiler ingest payloads.
  """

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
    AvailableTriggersAttrs,
    AutoTick,
    CmdCall,
    CompanionBridgeRequest,
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
    ExecutionModel,
    ExecutionRuntimeSnapshot,
    ExportTraceOpts,
    ExportTraceResult,
    InnerRuntimeModel,
    InjectTriggerAttrs,
    LaunchContext,
    ProtocolTxRxPayload,
    ReplayAttrs,
    ReplayRow,
    RuntimeExecEventPayload,
    RuntimeStatusEventPayload,
    ReloadAttrs,
    SaveConfigurationAttrs,
    RuntimeEventPayload,
    SessionAttrs,
    SnapshotContinueAttrs,
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

  @type core_ir :: map() | nil
  @type core_ir_expr :: map()
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

  @type protocol_error :: atom() | String.t() | tuple()

  @type protocol_wire_type :: Schema.wire_type()

  @type protocol_wire_slot :: Schema.wire_slot()

  @type protocol_key_ids :: WireSchema.key_ids()

  @type protocol_ctor_value :: ConstructorValue.t() | ConstructorValue.wire_value()

  @type protocol_schema_message :: Schema.message() | Schema.runtime_message()

  @type protocol_message_wire_value ::
          protocol_ctor_value() | wire_map() | String.t() | nil

  @type protocol_wire_scalar :: String.t() | integer() | float() | boolean()

  @type protocol_wire_arg ::
          protocol_ctor_value() | protocol_wire_scalar() | tuple() | wire_map() | nil

  @type protocol_wire_normalize_input :: protocol_wire_arg()

  @type init_model_values :: wire_map()

  @type debugger_contract :: Payload.wire_payload()

  @type elm_introspect :: debugger_contract()

  @type elmx_manifest :: wire_map()

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

  @type wire_map :: %{optional(String.t()) => wire_input(), optional(atom()) => wire_input()}

  @type companion_bridge_payload ::
          boolean()
          | wire_map()
          | [wire_map()]
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

  @type companion_subscription_field_def :: %{
          required(:key) => String.t(),
          required(:label) => String.t(),
          required(:type) => :boolean | :integer | :string,
          optional(:setting) => String.t(),
          required(:default) => boolean() | integer() | String.t()
        }

  @type companion_subscription_contract :: %{
          required(:source) => String.t(),
          required(:target_suffixes) => [String.t()],
          required(:payload) => atom(),
          optional(:trigger_slugs) => [String.t()],
          optional(:fields) => [companion_subscription_field_def()],
          optional(:plain_result) => boolean(),
          optional(:ok_result_variant) => String.t()
        }

  @type companion_injection_form_data :: wire_map()

  @type pending_protocol_delivery_item ::
          PendingProtocolDeliveryItem.t() | PendingProtocolDeliveryItem.wire_item()

  @type pending_http_followup_item ::
          PendingHttpFollowupItem.t() | PendingHttpFollowupItem.wire_item()

  @type companion_subscription_source :: %{
          optional(:source) => String.t(),
          optional(:plain_result) => boolean(),
          optional(:ok_result_variant) => String.t()
        }

  @type protocol_metadata_value :: wire_scalar() | wire_map() | nil

  @type phone_to_watch_message_value :: protocol_ctor_value() | wire_map()

  @type phone_to_watch_payload :: subscription_payload() | boolean() | String.t()

  @type elmc_wire_ctor_call :: wire_ctor()

  @type elmc_wire_ctor_value :: wire_ctor()

  @type simulator_command_input ::
          elmc_wire_ctor_value() | elmc_wire_ctor_call() | wire_scalar() | wire_map()

  @type subscription_row_input :: DisabledSubscription.wire_map() | wire_map()

  @type runtime_model_patch :: %{optional(String.t()) => wire_input()}

  @type timeline_step_message_value :: subscription_payload() | wire_scalar() | nil

  @type debugger_timeline_payload :: wire_map()

  @type protocol_binding_record :: %{
          optional(String.t()) => wire_input()
        }

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

  @type eval_context :: wire_map()

  @type protocol_var_bindings :: wire_map()

  @type screen_dimension_patch :: %{
          optional(String.t()) => pos_integer()
        }

  @type device_preview_map :: %{
          optional(String.t()) => String.t() | integer() | boolean()
        }

  @type device_preview :: nil | boolean() | String.t() | device_preview_map()

  @type elm_maybe :: protocol_ctor_value() | wire_map() | nil

  @type protocol_inbound_row :: %{
          optional(String.t()) => String.t() | wire_map() | list() | nil,
          optional(atom()) => String.t() | wire_map() | list() | nil
        }

  @type subscription_payload :: wire_map() | protocol_ctor_value() | wire_scalar()

  @type view_output_row :: Elmx.Types.view_output_row()

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

  @type runtime_fingerprint :: wire_map()

  @type fingerprint_compare_result :: wire_map()

  @type fingerprint_compare_surface_row :: wire_map()

  @type normalized_export_term :: wire_scalar() | wire_map() | [normalized_export_term()]

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

  @type execution_fallback_reason :: atom() | String.t() | tuple()

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
