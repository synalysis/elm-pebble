defmodule Ide.Debugger.Types do
  @moduledoc """
  Shared types for debugger runtime state, timeline rows, and compiler ingest payloads.
  """

  alias ElmEx.CoreIR
  alias ElmEx.CoreIR.Types, as: CoreIRTypes
  alias ElmExecutor.Runtime.SemanticExecutor.Types.ViewOutputRow
  alias ElmExecutor.Runtime.SemanticExecutor.Types.ViewTreeNode
  alias Ide.Debugger.ElmIntrospect.Payload
  alias Ide.Debugger.Protocol.{ConstructorValue, Event, Schema}
  alias Ide.Debugger.RuntimeArtifacts.Types, as: RuntimeArtifactsTypes
  alias Ide.Debugger.Types.{
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
    ElmIntrospectEventPayload,
    ElmcDiagnosticPreview,
    ElmcEventPayload,
    ElmcSurfaceFields,
    HotReloadEventPayload,
    MessageInEventPayload,
    PackageCmdEventPayload,
    PackageCmdErrorEventPayload,
    ImportTraceBody,
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

  @type core_ir :: CoreIR.t() | CoreIRTypes.wire_map() | map() | nil
  @type core_ir_expr :: CoreIRTypes.Expr.t() | CoreIRTypes.Expr.wire_expr()
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

  @type elm_introspect_event_payload ::
          ElmIntrospectEventPayload.t() | ElmIntrospectEventPayload.wire_map()

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

  @type protocol_ctor_value :: ConstructorValue.t() | ConstructorValue.wire_value()

  @type protocol_schema_message :: Schema.message() | map()

  @type protocol_message_wire_value :: protocol_ctor_value() | map() | String.t() | nil

  @type protocol_wire_scalar :: String.t() | integer() | float() | boolean()

  @type protocol_wire_arg ::
          protocol_ctor_value() | protocol_wire_scalar() | tuple() | map() | nil

  @type protocol_wire_normalize_input :: protocol_wire_arg()

  @type init_model_values :: wire_map()

  @type elm_introspect :: Payload.wire_payload()

  @type inner_runtime_model :: InnerRuntimeModel.t() | InnerRuntimeModel.wire_map()

  @type app_model :: AppModel.t() | AppModel.wire_map()

  @type shell :: Shell.t() | Shell.wire_map()

  @type execution_model :: ExecutionModel.t() | ExecutionModel.wire_map()

  @type protocol_message :: protocol_ctor_value()

  @type runtime_model :: execution_model()

  @type surface_target :: :watch | :companion | :phone

  @type surface_label_input :: surface_target() | String.t() | atom() | nil

  @type wire_scalar :: String.t() | integer() | float() | boolean() | nil

  @type wire_input :: wire_scalar() | list() | map()

  @type wire_map :: %{optional(String.t()) => wire_input(), optional(atom()) => wire_input()}

  @type companion_bridge_payload ::
          boolean()
          | map()
          | [map()]
          | String.t()
          | integer()
          | nil

  @type device_preview_map :: %{
          optional(String.t()) => String.t() | integer() | boolean()
        }

  @type device_preview :: nil | boolean() | String.t() | device_preview_map()

  @type elm_maybe :: protocol_ctor_value() | map() | nil

  @type protocol_inbound_row :: %{
          optional(String.t()) => String.t() | map() | list() | nil,
          optional(atom()) => String.t() | map() | list() | nil
        }

  @type subscription_payload :: map() | protocol_ctor_value() | wire_scalar()

  @type view_output_node :: ViewOutputRow.t() | ViewOutputRow.wire_row()

  @type view_output_tree :: ViewTreeNode.view_tree() | ViewTreeNode.t()

  @type runtime_step_result :: RuntimeStepResult.t() | RuntimeStepResult.wire_result()

  @type replay_step_message :: ReplayRow.t()

  @type runtime_fingerprint :: wire_map()

  @type normalized_export_term :: map() | list() | wire_scalar()

  @type static_task_result :: map() | integer() | {map(), map()}

  @type runtime_view_nodes :: [view_output_node()]

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
          | {:invalid_elm_executor_result, execution_fallback_reason()}
          | {:elmc_runtime_executor_failed, execution_fallback_reason()}
          | {:invalid_elmc_runtime_result, execution_fallback_reason()}
          | {:elmc_runtime_unavailable, execution_fallback_reason()}
          | {:external_runtime_executor_failed, execution_fallback_reason()}
          | {:invalid_external_runtime_result, execution_fallback_reason()}
          | execution_fallback_reason()

  @type http_executor_error :: :invalid_http_command | protocol_error()

  @type param_list :: [String.t()]
end
