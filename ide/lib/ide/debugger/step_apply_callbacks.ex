defmodule Ide.Debugger.StepApplyCallbacks do
  @moduledoc false

  alias Ide.Debugger.CompanionBridge.Runtime, as: CompanionBridgeRuntime
  alias Ide.Debugger.DeviceDataResponses
  alias Ide.Debugger.GeolocationResponses
  alias Ide.Debugger.ProtocolEvents
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.ProtocolRuntimeMetadata
  alias Ide.Debugger.RuntimeFollowups
  alias Ide.Debugger.RuntimeModelHydrate
  alias Ide.Debugger.RuntimeModelNormalize
  alias Ide.Debugger.SampleViewTrees
  alias Ide.Debugger.StepMessageValue
  alias Ide.Debugger.SurfaceCompileArtifacts
  alias Ide.Debugger.Types

  @type host :: %{
          required(:introspect_for) => (map(), Types.surface_target() -> map()),
          required(:protocol_events_ctx) => (-> ProtocolEvents.ctx()),
          required(:protocol_rx_ctx) => (-> ProtocolRx.ctx()),
          required(:source_root_for_target) => (Types.surface_target() -> String.t()),
          required(:append_runtime_exec) => (map(), Types.surface_target(), map() -> map()),
          required(:append_event) => (map(), String.t(), map() -> map()),
          required(:append_debugger_event) =>
            (map(), String.t(), Types.surface_target(), String.t(), String.t(), map() | nil -> map()),
          required(:maybe_append_runtime_status) => (map(), Types.surface_target() -> map())
        }

  @type deps :: %{
          required(:host) => host(),
          required(:surface_compile) => SurfaceCompileArtifacts.attach_ctx(),
          required(:protocol_events) => ProtocolEvents.ctx(),
          required(:protocol_rx) => ProtocolRx.ctx(),
          required(:device_data) => DeviceDataResponses.apply_ctx(),
          required(:geolocation) => GeolocationResponses.apply_ctx(),
          required(:companion_bridge) => CompanionBridgeRuntime.ctx(),
          required(:runtime_followups) => RuntimeFollowups.apply_ctx()
        }

  # Return type stays map() — same keys as StepApply.ctx() but Dialyzer widens callback fields.
  @spec build(deps()) :: map()
  def build(%{} = deps) do
    host = Map.fetch!(deps, :host)
    surface_compile = Map.fetch!(deps, :surface_compile)
    protocol_events = Map.fetch!(deps, :protocol_events)
    protocol_rx = Map.fetch!(deps, :protocol_rx)
    device_data = Map.fetch!(deps, :device_data)
    geolocation = Map.fetch!(deps, :geolocation)
    companion_bridge = Map.fetch!(deps, :companion_bridge)
    runtime_followups = Map.fetch!(deps, :runtime_followups)

    %{
      ensure_compile_artifacts: &ensure_compile_artifacts(&1, &2, surface_compile),
      hydrate_runtime_model: &RuntimeModelHydrate.for_message/3,
      normalize_message_value: &normalize_message_value(&1, &2, &3, &4, protocol_events),
      normalize_runtime_patch: &RuntimeModelNormalize.patch_values/2,
      patched_runtime_model_fields: &RuntimeModelHydrate.patched_fields/1,
      preserve_protocol_metadata: &ProtocolRuntimeMetadata.preserve/2,
      default_view_tree: &SampleViewTrees.default_for_target/1,
      introspect_for: host.introspect_for,
      protocol_events_ctx: fn -> protocol_events end,
      protocol_rx_ctx: fn -> protocol_rx end,
      source_root_for_target: host.source_root_for_target,
      append_runtime_exec: host.append_runtime_exec,
      append_event: host.append_event,
      append_debugger_event: host.append_debugger_event,
      maybe_append_runtime_status: host.maybe_append_runtime_status,
      device_data_responses: &device_data_responses(&1, &2, &3, &4, &5, device_data),
      geolocation_response: &geolocation_response(&1, &2, &3, &4, &5, geolocation),
      companion_bridge_command_responses:
        &companion_bridge_command_responses(&1, &2, &3, &4, &5, companion_bridge),
      companion_bridge_responses: &companion_bridge_responses(&1, &2, &3, companion_bridge),
      static_task_followups: &static_task_followups(&1, &2, &3, &4, &5, runtime_followups),
      runtime_followups: &runtime_followups_after_step(&1, &2, &3, &4, &5, runtime_followups)
    }
  end

  @spec ensure_compile_artifacts(
          Types.runtime_state(),
          Types.surface_target(),
          SurfaceCompileArtifacts.attach_ctx()
        ) :: Types.runtime_state()
  def ensure_compile_artifacts(state, target, surface_compile) do
    SurfaceCompileArtifacts.ensure_attached(state, target, surface_compile)
  end

  @spec normalize_message_value(
          Types.runtime_state(),
          Types.surface_target(),
          Types.subscription_payload() | nil,
          Types.app_model(),
          ProtocolEvents.ctx()
        ) :: Types.subscription_payload() | nil
  def normalize_message_value(state, target, message_value, model, protocol_events) do
    StepMessageValue.normalize(state, target, message_value, model, fn -> protocol_events end)
  end

  @spec device_data_responses(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          Types.app_model(),
          String.t(),
          DeviceDataResponses.apply_ctx()
        ) :: Types.runtime_state()
  def device_data_responses(state, target, message, model, source, device_data) do
    DeviceDataResponses.apply_after_step(state, target, message, model, source, device_data)
  end

  @spec geolocation_response(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          Types.app_model(),
          String.t(),
          GeolocationResponses.apply_ctx()
        ) :: Types.runtime_state()
  def geolocation_response(state, target, message, model, source, geolocation) do
    GeolocationResponses.apply_after_step(state, target, message, model, source, geolocation)
  end

  @spec companion_bridge_command_responses(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          Types.app_model(),
          String.t(),
          CompanionBridgeRuntime.ctx()
        ) :: Types.runtime_state()
  def companion_bridge_command_responses(state, target, message, model, message_source, companion_bridge) do
    Ide.Debugger.CompanionBridgeEffects.apply_command_responses(
      state,
      target,
      message,
      model,
      message_source,
      companion_bridge
    )
  end

  @spec companion_bridge_responses(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          CompanionBridgeRuntime.ctx()
        ) :: Types.runtime_state()
  def companion_bridge_responses(state, target, message_source, companion_bridge) do
    Ide.Debugger.CompanionBridgeEffects.apply_responses(state, target, message_source, companion_bridge)
  end

  @spec static_task_followups(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          Types.subscription_payload() | nil,
          String.t(),
          RuntimeFollowups.apply_ctx()
        ) :: Types.runtime_state()
  def static_task_followups(state, target, message, message_value, source, runtime_followups) do
    RuntimeFollowups.apply_static_task_after_step(
      state,
      target,
      message,
      message_value,
      source,
      runtime_followups
    )
  end

  @spec runtime_followups_after_step(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          String.t(),
          list(),
          RuntimeFollowups.apply_ctx()
        ) :: Types.runtime_state()
  def runtime_followups_after_step(state, target, message, source, followups, runtime_followups) do
    RuntimeFollowups.apply_after_step(state, target, message, source, followups, runtime_followups)
  end
end
