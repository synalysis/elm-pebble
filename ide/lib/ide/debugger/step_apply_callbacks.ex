defmodule Ide.Debugger.StepApplyCallbacks do
  @moduledoc false

  alias Ide.Debugger.CompanionBridge.Runtime, as: CompanionBridgeRuntime
  alias Ide.Debugger.StepApply
  alias Ide.Debugger.DeviceDataResponses
  alias Ide.Debugger.GeolocationResponses
  alias Ide.Debugger.ProtocolEvents
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.ProtocolRuntimeMetadata
  alias Ide.Debugger.RuntimeFollowups
  alias Ide.Debugger.RuntimeInitApply
  alias Ide.Debugger.RuntimeModelNormalize
  alias Ide.Debugger.SampleViewTrees
  alias Ide.Debugger.StepMessageValue
  alias Ide.Debugger.SurfaceCompileArtifacts
  alias Ide.Debugger.Types

  @type host :: %{
          required(:introspect_for) => (Types.runtime_state(), Types.surface_target() ->
                                          Types.elm_introspect()),
          required(:protocol_events_ctx) => (-> ProtocolEvents.ctx()),
          required(:protocol_rx_ctx) => (-> ProtocolRx.ctx()),
          required(:source_root_for_target) => (Types.surface_target() -> String.t()),
          required(:append_runtime_exec) => (Types.runtime_state(),
                                             Types.surface_target(),
                                             Types.RuntimeExecEventPayload.extra() ->
                                               Types.runtime_state()),
          required(:append_event) => (Types.runtime_state(),
                                      String.t(),
                                      Types.debugger_timeline_payload() ->
                                        Types.runtime_state()),
          required(:append_debugger_event) => (Types.runtime_state(),
                                               String.t(),
                                               Types.surface_target(),
                                               String.t(),
                                               String.t(),
                                               Types.timeline_step_message_value() ->
                                                 Types.runtime_state()),
          required(:maybe_append_runtime_status) => (Types.runtime_state(),
                                                     Types.surface_target() ->
                                                       Types.runtime_state())
        }

  @type deps :: %{
          required(:host) => host(),
          required(:surface_compile) => SurfaceCompileArtifacts.attach_ctx(),
          required(:runtime_init) => RuntimeInitApply.ctx(),
          required(:protocol_events) => ProtocolEvents.ctx(),
          required(:protocol_rx) => ProtocolRx.ctx(),
          required(:device_data) => DeviceDataResponses.apply_ctx(),
          required(:geolocation) => GeolocationResponses.apply_ctx(),
          required(:companion_bridge) => CompanionBridgeRuntime.ctx(),
          required(:runtime_followups) => RuntimeFollowups.apply_ctx()
        }

  @spec build(deps()) :: StepApply.ctx()
  def build(%{} = deps) do
    host = Map.fetch!(deps, :host)
    surface_compile = Map.fetch!(deps, :surface_compile)
    runtime_init = Map.fetch!(deps, :runtime_init)
    protocol_events = Map.fetch!(deps, :protocol_events)
    protocol_rx = Map.fetch!(deps, :protocol_rx)
    device_data = Map.fetch!(deps, :device_data)
    geolocation = Map.fetch!(deps, :geolocation)
    companion_bridge = Map.fetch!(deps, :companion_bridge)
    runtime_followups = Map.fetch!(deps, :runtime_followups)

    %{
      ensure_compile_artifacts: &ensure_compile_artifacts(&1, &2, surface_compile, runtime_init),
      normalize_message_value: &normalize_message_value(&1, &2, &3, &4, protocol_events),
      normalize_runtime_patch: &RuntimeModelNormalize.patch_values/2,
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
      device_data_responses: &device_data_responses(&1, &2, &3, &4, &5, &6, device_data),
      geolocation_response: &geolocation_response(&1, &2, &3, &4, &5, geolocation),
      companion_bridge_command_responses:
        &companion_bridge_command_responses(&1, &2, &3, &4, &5, companion_bridge),
      companion_bridge_responses: &companion_bridge_responses(&1, &2, &3, companion_bridge),
      static_task_followups: &static_task_followups(&1, &2, &3, &4, &5, runtime_followups),
      runtime_followups:
        &runtime_followups_after_step(&1, &2, &3, &4, &5, %{ctx: runtime_followups})
    }
  end

  @spec ensure_compile_artifacts(
          Types.runtime_state(),
          Types.surface_target(),
          SurfaceCompileArtifacts.attach_ctx(),
          RuntimeInitApply.ctx()
        ) :: Types.runtime_state()
  def ensure_compile_artifacts(state, target, surface_compile, runtime_init) do
    state
    |> SurfaceCompileArtifacts.ensure_attached(target, surface_compile)
    |> RuntimeInitApply.ensure_applied(target, runtime_init)
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
          Types.subscription_payload() | nil,
          DeviceDataResponses.apply_ctx()
        ) :: Types.runtime_state()
  def device_data_responses(state, target, message, model, source, message_value, device_data) do
    DeviceDataResponses.apply_after_step(
      state,
      target,
      message,
      model,
      source,
      device_data,
      message_value
    )
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
  def companion_bridge_command_responses(
        state,
        target,
        message,
        model,
        message_source,
        companion_bridge
      ) do
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
    Ide.Debugger.CompanionBridgeEffects.apply_responses(
      state,
      target,
      message_source,
      companion_bridge
    )
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
          %{required(:ctx) => RuntimeFollowups.apply_ctx()}
        ) :: Types.runtime_state()
  def runtime_followups_after_step(state, target, message, source, followups, %{
        ctx: followup_ctx
      }) do
    RuntimeFollowups.apply_after_step(
      state,
      target,
      message,
      source,
      followups,
      followup_ctx
    )
  end
end
