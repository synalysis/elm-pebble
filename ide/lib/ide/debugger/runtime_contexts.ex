defmodule Ide.Debugger.RuntimeContexts do
  @moduledoc false

  alias Ide.Debugger.CompanionBridgeContext
  alias Ide.Debugger.DeviceDataResponses
  alias Ide.Debugger.GeolocationResponses
  alias Ide.Debugger.HotReloadContext
  alias Ide.Debugger.HotReloadEvents
  alias Ide.Debugger.HotReloadSurface
  alias Ide.Debugger.InitCmdFollowups
  alias Ide.Debugger.InitSurfaceEffectsContext
  alias Ide.Debugger.IntrospectContexts
  alias Ide.Debugger.ProtocolContexts
  alias Ide.Debugger.RuntimeExecutorConfig
  alias Ide.Debugger.RuntimeFollowups
  alias Ide.Debugger.SimulatorWatchDeliveryContext
  alias Ide.Debugger.StepApplyContext
  alias Ide.Debugger.StepFollowupContexts
  alias Ide.Debugger.SubscriptionWireContexts
  alias Ide.Debugger.SurfaceCompileArtifacts
  alias Ide.Debugger.SurfaceCompileArtifactsContext
  alias Ide.Debugger.AutoFireRuntime
  alias Ide.Debugger.CompanionBridge.Runtime, as: CompanionBridgeRuntime
  alias Ide.Debugger.HotReload
  alias Ide.Debugger.ProtocolEvents
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.StepApply
  alias Ide.Debugger.StepMessageValue
  alias Ide.Debugger.SubscriptionTriggerWire
  alias Ide.Debugger.TriggerMessageSurface
  alias Ide.Debugger.InitSurfaceEffects
  alias Ide.Debugger.SubscriptionResponses
  alias Ide.Debugger.TriggerInjection
  alias Ide.Debugger.TriggerInjectionContext
  alias Ide.Debugger.TriggerSurface
  alias Ide.Debugger.Types

  @type step_followup_host :: StepFollowupContexts.host()

  @type host :: %{
          required(:append_event) => (map(), String.t(), map() -> map()),
          required(:append_debugger_event) =>
            (map(), String.t(), Types.surface_target(), String.t(), String.t() -> map()),
          required(:apply_step_once) =>
            (map(), Types.surface_target(), String.t(), Types.subscription_payload() | map() | nil,
             String.t(), String.t() -> map()),
          required(:apply_step_without_value) =>
            (map(), Types.surface_target(), String.t(), String.t(), String.t() -> map()),
          required(:source_root_for_target) => (Types.surface_target() -> String.t()),
          required(:session_key_from_state) => (map() -> String.t() | nil),
          required(:simulator_settings_from_state) => (map() -> map()),
          required(:introspect_for) => (map(), Types.surface_target() -> map()),
          required(:surface_app_model) => (map(), Types.surface_target() -> map()),
          required(:normalize_step_target) => (Types.wire_input() -> Types.surface_target()),
          required(:model_active?) => (map(), Types.surface_target(), map() -> boolean()),
          required(:subscription_row_enabled?) => (map(), Types.surface_target(), map() -> boolean()),
          required(:auto_fire_row_enabled?) => (map(), Types.surface_target(), map() -> boolean()),
          required(:simulator_now) => (map(), Types.surface_target() -> NaiveDateTime.t()),
          required(:append_runtime_exec) => (map(), Types.surface_target(), map() -> map()),
          required(:trigger_message_for_surface) =>
            (map(), Types.surface_target(), String.t(), String.t() | nil -> String.t()),
          required(:attach_subscription_payload) =>
            (map(), Types.surface_target(), String.t(), String.t() -> String.t()),
          required(:merge_runtime_artifacts) =>
            (map(), Types.surface_target(), map() -> map()),
          required(:apply_subscription_ok_response) =>
            (map(), Types.surface_target(), String.t(), map(), String.t(), String.t() -> map()),
          required(:maybe_attach_compile_artifacts) =>
            (map(), Types.surface_target(), map() -> map()),
          required(:maybe_append_runtime_status) => (map(), Types.surface_target() -> map()),
          required(:maybe_append_runtime_status_after_init) =>
            (map(), Types.surface_target(), map(), map() -> map()),
          required(:maybe_append_elm_introspect) => (map(), map() | nil -> map()),
          required(:maybe_append_runtime_exec) => (map(), String.t() -> map()),
          required(:maybe_append_phone_view_render) => (map(), String.t() -> map()),
          optional(:default_auto_fire_interval_ms) => pos_integer()
        }

  @type t :: %{
          step_followup_host: step_followup_host(),
          device_data: DeviceDataResponses.apply_ctx(),
          runtime_followups: RuntimeFollowups.apply_ctx(),
          geolocation: GeolocationResponses.apply_ctx(),
          subscription_responses: SubscriptionResponses.apply_ctx(),
          surface_compile: SurfaceCompileArtifactsContext.host(),
          simulator_watch_delivery: SimulatorWatchDeliveryContext.host(),
          companion_bridge: CompanionBridgeRuntime.ctx(),
          protocol_events: ProtocolEvents.ctx(),
          protocol_rx: ProtocolRx.ctx(),
          step_apply: StepApply.ctx(),
          trigger_injection: TriggerInjection.host(),
          subscription_payload: TriggerMessageSurface.payload_ctx(),
          trigger_wire: SubscriptionTriggerWire.injection_modal_ctx(),
          tick_resolution: TriggerMessageSurface.resolve_ctx(),
          trigger_surface: TriggerSurface.candidates_ctx(),
          auto_fire: AutoFireRuntime.apply_ctx(),
          init_surface_effects: InitSurfaceEffects.ctx(),
          introspect_snapshot_apply: IntrospectContexts.snapshot_host(),
          introspect_merge: IntrospectContexts.merge_host(),
          hot_reload_events: HotReloadEvents.host()
        }

  @spec build(host()) :: t()
  def build(host) when is_map(host) do
    step_followup = step_followup_host(host)

    protocol_events =
      ProtocolContexts.events_ctx(%{
        introspect_for: host.introspect_for,
        simulator_settings_from_state: host.simulator_settings_from_state,
        session_key_from_state: host.session_key_from_state,
        surface_app_model: host.surface_app_model
      })

    protocol_events_fn = fn -> protocol_events end

    trigger_surface = %{
      introspect_for: host.introspect_for,
      source_root_for_target: host.source_root_for_target
    }

    trigger_candidates = fn state, target ->
      TriggerSurface.candidates(state, target, trigger_surface)
    end

    protocol_rx =
      ProtocolContexts.rx_ctx(%{
        append_event: host.append_event,
        append_debugger_event: host.append_debugger_event,
        append_runtime_exec_event_for_target: host.append_runtime_exec,
        source_root_for_target: host.source_root_for_target,
        introspect_for: host.introspect_for,
        apply_step_once: host.apply_step_once,
        protocol_events_ctx: protocol_events_fn
      })

    protocol_rx_fn = fn -> protocol_rx end

    simulator_watch_delivery =
      SimulatorWatchDeliveryContext.build(%{
        apply_step_once: host.apply_step_once,
        trigger_candidates: trigger_candidates,
        model_active?: host.model_active?,
        trigger_message_for_surface: host.trigger_message_for_surface,
        simulator_settings: host.simulator_settings_from_state,
        protocol_events_ctx: protocol_events_fn
      })

    companion_bridge =
      CompanionBridgeContext.build(%{
        introspect_for: host.introspect_for,
        append_event: host.append_event,
        apply_step_once: host.apply_step_once,
        deliver_weather_to_watch: fn st ->
          Ide.Debugger.SimulatorWatchDelivery.deliver_weather(st, simulator_watch_delivery)
        end,
        settings: host.simulator_settings_from_state
      })

    device_data = StepFollowupContexts.device_data(step_followup)
    runtime_followups = StepFollowupContexts.runtime_followups(step_followup)
    geolocation = StepFollowupContexts.geolocation(step_followup)
    subscription_responses = StepFollowupContexts.subscription_responses(step_followup)

    surface_compile =
      SurfaceCompileArtifactsContext.build(%{
        session_key_from_state: host.session_key_from_state,
        source_root_for_target: host.source_root_for_target,
        merge_runtime_artifacts: host.merge_runtime_artifacts
      })

    step_apply =
      StepApplyContext.build(%{
        ensure_compile_artifacts: fn st, target ->
          SurfaceCompileArtifacts.ensure_attached(st, target, surface_compile)
        end,
        normalize_message_value: fn state, target, message_value, model ->
          StepMessageValue.normalize(state, target, message_value, model, protocol_events_fn)
        end,
        introspect_for: host.introspect_for,
        protocol_events_ctx: protocol_events_fn,
        protocol_rx_ctx: protocol_rx_fn,
        source_root_for_target: host.source_root_for_target,
        append_runtime_exec: host.append_runtime_exec,
        append_event: host.append_event,
        append_debugger_event: host.append_debugger_event,
        maybe_append_runtime_status: host.maybe_append_runtime_status,
        device_data_responses: fn st, target, message, model, source ->
          DeviceDataResponses.apply_after_step(st, target, message, model, source, device_data)
        end,
        geolocation_response: fn st, target, message, model, source ->
          GeolocationResponses.apply_after_step(st, target, message, model, source, geolocation)
        end,
        companion_bridge_command_responses: fn st, target, message, model, message_source ->
          Ide.Debugger.CompanionBridgeEffects.apply_command_responses(
            st,
            target,
            message,
            model,
            message_source,
            companion_bridge
          )
        end,
        companion_bridge_responses: fn st, target, message_source ->
          Ide.Debugger.CompanionBridgeEffects.apply_responses(st, target, message_source, companion_bridge)
        end,
        static_task_followups: fn st, target, message, message_value, source ->
          RuntimeFollowups.apply_static_task_after_step(
            st,
            target,
            message,
            message_value,
            source,
            runtime_followups
          )
        end,
        runtime_followups: fn st, target, message, source, followups ->
          RuntimeFollowups.apply_after_step(st, target, message, source, followups, runtime_followups)
        end
      })

    init_surface_effects =
      InitSurfaceEffectsContext.build(%{
        append_event: host.append_event,
        apply_step_once: host.apply_step_once,
        apply_device_data_followups: fn st, target, message, model, source ->
          DeviceDataResponses.apply_after_step(st, target, message, model, source, device_data)
        end,
        apply_subscription_ok_response: host.apply_subscription_ok_response,
        protocol_events_ctx: protocol_events_fn,
        protocol_rx_ctx: protocol_rx_fn,
        companion_bridge_ctx: fn -> companion_bridge end,
        source_root_for_target: host.source_root_for_target
      })

    introspect_snapshot_apply =
      IntrospectContexts.snapshot_apply(%{
        executor: RuntimeExecutorConfig.module(),
        attach_compile_artifacts: host.maybe_attach_compile_artifacts,
        append_event: host.append_event,
        append_debugger_event: host.append_debugger_event,
        runtime_status_after_init: host.maybe_append_runtime_status_after_init,
        apply_runtime_followups: fn st, target, message, source, followups ->
          followups =
            if init_runtime_followups?(message, source) do
              InitCmdFollowups.merge_followups(followups, host.introspect_for.(st, target))
            else
              followups
            end

          RuntimeFollowups.apply_after_step(st, target, message, source, followups, runtime_followups)
        end,
        protocol_rx_ctx: protocol_rx_fn
      })

    introspect_merge =
      IntrospectContexts.merge(%{
        snapshot_apply_ctx: introspect_snapshot_apply,
        init_surface_effects_ctx: fn -> init_surface_effects end,
        refresh_runtime_preview_for_target: &RuntimeExecutorConfig.refresh_for_target/2,
        apply_simulator_settings: fn st ->
          st
          |> Ide.Debugger.SimulatorSurfaceSettings.apply_to_state()
          |> Ide.Debugger.CompanionBridgeEffects.apply_simulator_settings_responses(
            companion_bridge
          )
        end
      })

    %{
      step_followup_host: step_followup,
      device_data: device_data,
      runtime_followups: runtime_followups,
      geolocation: geolocation,
      subscription_responses: subscription_responses,
      surface_compile: surface_compile,
      simulator_watch_delivery: simulator_watch_delivery,
      companion_bridge: companion_bridge,
      protocol_events: protocol_events,
      protocol_rx: protocol_rx,
      step_apply: step_apply,
      subscription_payload:
        SubscriptionWireContexts.payload(%{
          introspect: host.introspect_for,
          settings: host.simulator_settings_from_state
        }),
      trigger_wire:
        SubscriptionWireContexts.trigger_wire(%{
          introspect_for: host.introspect_for,
          normalize_target: host.normalize_step_target
        }),
      tick_resolution:
        SubscriptionWireContexts.tick_resolution(%{
          introspect_for: host.introspect_for,
          attach_payload: host.attach_subscription_payload
        }),
      trigger_surface: trigger_surface,
      trigger_injection: TriggerInjectionContext.build(host),
      auto_fire:
        SubscriptionWireContexts.auto_fire(%{
          trigger_candidates: trigger_candidates,
          trigger_message: host.trigger_message_for_surface,
          apply_step: host.apply_step_once,
          subscription_row_enabled?: host.subscription_row_enabled?,
          auto_fire_row_enabled?: host.auto_fire_row_enabled?,
          simulator_now: host.simulator_now,
          source_root_for_target: host.source_root_for_target,
          default_interval_ms: Map.get(host, :default_auto_fire_interval_ms, 1_000)
        }),
      init_surface_effects: init_surface_effects,
      introspect_snapshot_apply: introspect_snapshot_apply,
      introspect_merge: introspect_merge,
      hot_reload_events: %{
        append_event: host.append_event,
        maybe_append_elm_introspect: host.maybe_append_elm_introspect,
        maybe_append_runtime_exec: host.maybe_append_runtime_exec,
        maybe_append_phone_view_render: host.maybe_append_phone_view_render
      }
    }
  end

  @spec hot_reload_context(t(), String.t() | nil, String.t(), String.t()) :: HotReload.ctx()
  def hot_reload_context(%{introspect_merge: introspect_merge, hot_reload_events: hot_reload_events}, rel_path, source, source_root) do
    HotReloadContext.build(rel_path, source, %{
      put_placeholder_views: &HotReloadSurface.put_view_trees/4,
      merge_introspect: fn st ->
        Ide.Debugger.ElmIntrospectSnapshot.merge_from_source(st, rel_path, source, source_root, introspect_merge)
      end,
      append_reload_events: fn st, reason, rp, revision, root, intro_payload ->
        HotReloadEvents.append(st, reason, rp, revision, root, intro_payload, hot_reload_events)
      end
    })
  end

  defp init_runtime_followups?(message, source) when is_binary(message) and is_binary(source) do
    message in ["init"] and source in ["init", "init_device_data"]
  end

  defp init_runtime_followups?(_message, _source), do: false

  defp step_followup_host(host) do
    %{
      append_event: host.append_event,
      source_root_for_target: host.source_root_for_target,
      apply_step_without_value: host.apply_step_without_value,
      apply_step_with_value: host.apply_step_once,
      introspect_for: host.introspect_for,
      simulator_settings: host.simulator_settings_from_state,
      track_http_command: &RuntimeFollowups.track_http_command/2
    }
  end
end
