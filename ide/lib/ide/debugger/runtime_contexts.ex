defmodule Ide.Debugger.RuntimeContexts do
  @moduledoc false

  alias Ide.Debugger.AutoFireRuntime
  alias Ide.Debugger.CompanionBridge.Runtime, as: CompanionBridgeRuntime
  alias Ide.Debugger.CompanionBridgeContext
  alias Ide.Debugger.DebuggerContractSnapshot
  alias Ide.Debugger.DeviceDataResponses
  alias Ide.Debugger.GeolocationResponses
  alias Ide.Debugger.HotReload
  alias Ide.Debugger.HotReloadContext
  alias Ide.Debugger.HotReloadEvents
  alias Ide.Debugger.HotReloadSurface
  alias Ide.Debugger.InitSurfaceEffects
  alias Ide.Debugger.InitSurfaceEffectsContext
  alias Ide.Debugger.IntrospectContexts
  alias Ide.Debugger.ProtocolContexts
  alias Ide.Debugger.ProtocolEvents
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.RuntimeExecutorConfig
  alias Ide.Debugger.RuntimeFollowups
  alias Ide.Debugger.RuntimeHost
  alias Ide.Debugger.SimulatorWatchDelivery
  alias Ide.Debugger.SimulatorWatchDeliveryContext
  alias Ide.Debugger.StepApply
  alias Ide.Debugger.StepApplyContext
  alias Ide.Debugger.StepFollowupContexts
  alias Ide.Debugger.SubscriptionResponses
  alias Ide.Debugger.SubscriptionTriggerWire
  alias Ide.Debugger.SubscriptionWireContexts
  alias Ide.Debugger.SurfaceCompileArtifacts
  alias Ide.Debugger.SurfaceCompileArtifactsContext
  alias Ide.Debugger.TriggerInjection
  alias Ide.Debugger.TriggerInjectionContext
  alias Ide.Debugger.TriggerMessageSurface
  alias Ide.Debugger.TriggerSurface

  @type host :: RuntimeHost.callbacks()

  @type t :: %{
          step_followup_host: StepFollowupContexts.host(),
          device_data: DeviceDataResponses.apply_ctx(),
          runtime_followups: RuntimeFollowups.apply_ctx(),
          geolocation: GeolocationResponses.apply_ctx(),
          subscription_responses: SubscriptionResponses.apply_ctx(),
          surface_compile: SurfaceCompileArtifacts.attach_ctx(),
          simulator_watch_delivery: SimulatorWatchDelivery.apply_ctx(),
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
          introspect_snapshot_apply: DebuggerContractSnapshot.apply_ctx(),
          introspect_merge: DebuggerContractSnapshot.merge_ctx(),
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
        introspect_for: host.introspect_for
      })

    companion_bridge =
      CompanionBridgeContext.build(%{
        introspect_for: host.introspect_for,
        append_event: host.append_event,
        apply_step_once: host.apply_step_once,
        settings: host.simulator_settings_from_state
      })

    device_data = StepFollowupContexts.device_data(step_followup)

    runtime_followups =
      step_followup
      |> StepFollowupContexts.runtime_followups()
      |> Map.put(:companion_bridge, companion_bridge)
      |> Map.put(:protocol_rx_ctx, protocol_rx_fn)

    geolocation = StepFollowupContexts.geolocation(step_followup)
    subscription_responses = StepFollowupContexts.subscription_responses(step_followup)

    surface_compile =
      SurfaceCompileArtifactsContext.build(%{
        session_key_from_state: host.session_key_from_state,
        source_root_for_target: host.source_root_for_target,
        merge_runtime_artifacts: host.merge_runtime_artifacts
      })

    step_apply_host = %{
      introspect_for: host.introspect_for,
      protocol_events_ctx: protocol_events_fn,
      protocol_rx_ctx: protocol_rx_fn,
      source_root_for_target: host.source_root_for_target,
      append_runtime_exec: host.append_runtime_exec,
      append_event: host.append_event,
      append_debugger_event: host.append_debugger_event,
      maybe_append_runtime_status: host.maybe_append_runtime_status
    }

    init_surface_effects =
      InitSurfaceEffectsContext.build(%{
        append_event: host.append_event,
        apply_step_once: host.apply_step_once,
        apply_subscription_ok_response: host.apply_subscription_ok_response,
        protocol_events_ctx: protocol_events_fn,
        protocol_rx_ctx: protocol_rx_fn,
        companion_bridge_ctx: fn -> companion_bridge end,
        source_root_for_target: host.source_root_for_target,
        introspect_for: host.introspect_for
      })

    introspect_snapshot_apply =
      IntrospectContexts.snapshot_apply(%{
        executor: RuntimeExecutorConfig.module(),
        attach_compile_artifacts: host.maybe_attach_compile_artifacts,
        append_event: host.append_event,
        append_debugger_event: host.append_debugger_event,
        runtime_status_after_init: host.maybe_append_runtime_status_after_init,
        apply_runtime_followups: fn st, target, message, source, followups ->
          RuntimeFollowups.apply_after_step(
            st,
            target,
            message,
            source,
            followups,
            runtime_followups
          )
        end,
        apply_init_device_data: fn state, target, followups ->
          DeviceDataResponses.apply_init_device_responses(state, target, device_data, followups)
        end,
        protocol_rx_ctx: protocol_rx_fn
      })

    runtime_init = %{
      snapshot_apply: introspect_snapshot_apply,
      init_surface_effects: init_surface_effects
    }

    step_apply =
      StepApplyContext.build(%{
        host: step_apply_host,
        surface_compile: surface_compile,
        runtime_init: runtime_init,
        protocol_events: protocol_events,
        protocol_rx: protocol_rx,
        device_data: device_data,
        geolocation: geolocation,
        companion_bridge: companion_bridge,
        runtime_followups: runtime_followups
      })

    introspect_merge =
      IntrospectContexts.merge(%{
        snapshot_apply_ctx: introspect_snapshot_apply,
        surface_compile: surface_compile,
        init_surface_effects_ctx: fn -> init_surface_effects end,
        refresh_runtime_preview_for_target: &RuntimeExecutorConfig.refresh_for_target/2,
        apply_simulator_settings: fn st ->
          st
          |> Ide.Debugger.SimulatorSurfaceSettings.apply_to_state()
          |> Ide.Debugger.CompanionBridgeEffects.apply_simulator_settings_responses(
            companion_bridge
          )
        end,
        deliver_companion_status_after_watch_init: fn st ->
          Ide.Debugger.CompanionBridgeEffects.apply_simulator_settings_responses(
            st,
            companion_bridge
          )
        end,
        protocol_rx_ctx: protocol_rx_fn
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
      trigger_injection: TriggerInjectionContext.build(host, device_data),
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
        maybe_append_contract: host.maybe_append_contract,
        maybe_append_runtime_exec: host.maybe_append_runtime_exec,
        maybe_append_phone_view_render: host.maybe_append_phone_view_render
      }
    }
  end

  @spec hot_reload_context(t(), String.t() | nil, String.t(), String.t()) :: HotReload.ctx()
  def hot_reload_context(
        %{introspect_merge: introspect_merge, hot_reload_events: hot_reload_events},
        rel_path,
        source,
        source_root
      ) do
    HotReloadContext.build(rel_path, source, %{
      put_placeholder_views: &HotReloadSurface.put_view_trees/4,
      merge_introspect: fn st ->
        Ide.Debugger.DebuggerContractSnapshot.merge_from_source(
          st,
          rel_path,
          source,
          source_root,
          introspect_merge
        )
      end,
      append_reload_events: fn st, reason, rp, revision, root, intro_payload ->
        HotReloadEvents.append(st, reason, rp, revision, root, intro_payload, hot_reload_events)
      end
    })
  end

  defp step_followup_host(host) do
    %{
      append_event: host.append_event,
      append_debugger_event: host.append_debugger_event,
      source_root_for_target: host.source_root_for_target,
      apply_step_without_value: host.apply_step_without_value,
      apply_step_with_value: host.apply_step_once,
      introspect_for: host.introspect_for,
      simulator_settings: host.simulator_settings_from_state,
      track_http_command: &RuntimeFollowups.track_http_command/2
    }
  end
end
