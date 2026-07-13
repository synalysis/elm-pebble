defmodule Ide.Debugger.RuntimeHub do
  @moduledoc false

  alias Ide.Debugger.HotReloadSurface
  alias Ide.Debugger.OperationHosts
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.RuntimeArtifactMerge
  alias Ide.Debugger.RuntimeContexts
  alias Ide.Debugger.RuntimeHost
  alias Ide.Debugger.RuntimeHostCallbacks
  alias Ide.Debugger.RuntimeStatusFacades
  alias Ide.Debugger.SessionDefaults
  alias Ide.Debugger.SimulatorSettings, as: DebuggerSimulatorSettings
  alias Ide.Debugger.StepApply
  alias Ide.Debugger.StepDepth
  alias Ide.Debugger.SubscriptionPayload
  alias Ide.Debugger.SubscriptionResponses
  alias Ide.Debugger.SurfaceAccess
  alias Ide.Debugger.SurfaceCompileArtifacts
  alias Ide.Debugger.SurfaceTargets
  alias Ide.Debugger.TriggerMessageSurface
  alias Ide.Debugger.TriggerSurface
  alias Ide.Debugger.Types

  @type append_event_fn ::
          (Types.runtime_state(), String.t(), Types.debugger_timeline_payload() ->
             Types.runtime_state())

  @type append_debugger_event_fn ::
          (Types.runtime_state(), String.t(), Types.surface_target(), String.t(), String.t() ->
             Types.runtime_state())

  @type update_fn ::
          (String.t(), (Types.runtime_state() -> Types.runtime_state()) ->
             {:ok, Types.runtime_state()})

  @type config :: %{
          required(:append_event) => append_event_fn(),
          required(:append_debugger_event) => append_debugger_event_fn(),
          required(:update) => update_fn(),
          required(:default_auto_fire_interval_ms) => pos_integer()
        }

  @spec contexts(config()) :: RuntimeContexts.t()
  def contexts(%{} = config) do
    stub_ctx =
      config
      |> then(&runtime_host_callbacks_impl(&1, :stub))
      |> RuntimeHost.build()
      |> RuntimeContexts.build()

    host =
      config
      |> then(&runtime_host_callbacks_impl(&1, {:built, stub_ctx}))
      |> RuntimeHost.build()

    ctx = RuntimeContexts.build(host)
    finalize_step_wiring(host, ctx)
  end

  @spec operation_deps(config()) :: OperationHosts.deps()
  def operation_deps(%{} = config) do
    ctx = contexts(config)

    %{
      apply_step_once: fn st, target, message, message_value, source, trigger ->
        apply_step_once(config, st, target, message, message_value, source, trigger, [], ctx)
      end,
      append_event: config.append_event,
      normalize_target: &SurfaceTargets.normalize/1,
      replay_label: &SurfaceTargets.replay_label/1,
      source_root_for_target: &SurfaceTargets.source_root/1,
      tick_message_for_surface: fn state, target ->
        tick_message_for_surface(ctx, state, target)
      end,
      update: config.update,
      contexts: fn -> ctx end,
      merge_runtime_artifacts: &RuntimeArtifactMerge.maybe_merge/3,
      refresh_from_artifacts: &Ide.Debugger.RuntimeExecutorConfig.refresh_from_artifacts/1
    }
  end

  @spec apply_step_once(
          config(),
          Types.runtime_state(),
          Types.surface_target(),
          String.t() | nil,
          String.t() | nil,
          String.t()
        ) :: Types.runtime_state()
  def apply_step_once(config, state, target, requested_message, source_override, trigger)
      when target in [:watch, :companion, :phone] do
    apply_step_once(config, state, target, requested_message, nil, source_override, trigger, [])
  end

  @spec apply_step_once(
          config(),
          Types.runtime_state(),
          Types.surface_target(),
          String.t() | nil,
          Types.subscription_payload() | nil,
          String.t() | nil,
          String.t(),
          keyword()
        ) :: Types.runtime_state()
  def apply_step_once(
        config,
        state,
        target,
        requested_message,
        message_value,
        source_override,
        trigger,
        opts
      )
      when target in [:watch, :companion, :phone] and is_list(opts) do
    apply_step_once(
      config,
      state,
      target,
      requested_message,
      message_value,
      source_override,
      trigger,
      opts,
      contexts(config)
    )
  end

  @spec apply_step_once(
          config(),
          Types.runtime_state(),
          Types.surface_target(),
          String.t() | nil,
          Types.subscription_payload() | nil,
          String.t() | nil,
          String.t(),
          keyword(),
          RuntimeContexts.t()
        ) :: Types.runtime_state()
  def apply_step_once(
        _config,
        state,
        target,
        requested_message,
        message_value,
        source_override,
        trigger,
        opts,
        ctx
      )
      when target in [:watch, :companion, :phone] and is_list(opts) do
    complete_step(
      state,
      target,
      requested_message,
      message_value,
      source_override,
      trigger,
      opts,
      ctx
    )
  end

  @spec complete_step(
          Types.runtime_state(),
          Types.surface_target(),
          String.t() | nil,
          Types.subscription_payload() | nil,
          String.t() | nil,
          String.t(),
          keyword(),
          RuntimeContexts.t()
        ) :: Types.runtime_state()
  def complete_step(
        state,
        target,
        requested_message,
        message_value,
        source_override,
        trigger,
        opts,
        %{step_apply: step_apply, companion_bridge: companion_bridge, protocol_rx: protocol_rx}
      )
      when target in [:watch, :companion, :phone] and is_list(opts) do
    StepDepth.enter()

    state =
      state
      |> StepApply.apply(
        target,
        requested_message,
        message_value,
        source_override,
        trigger,
        opts,
        step_apply
      )
      |> Ide.Debugger.CompanionBridge.Runtime.flush_deferred_steps(companion_bridge)

    if StepDepth.leave() == 0 do
      ProtocolRx.flush_inline_protocol_deliveries(state, protocol_rx)
    else
      state
    end
  end

  @spec finalize_step_wiring(RuntimeHost.callbacks(), RuntimeContexts.t()) ::
          RuntimeContexts.t()
  defp finalize_step_wiring(host, ctx) do
    step_apply = Map.fetch!(ctx, :step_apply)
    protocol_rx = Map.fetch!(ctx, :protocol_rx)
    companion_bridge = Map.fetch!(ctx, :companion_bridge)

    # Deferred bridge steps only run Elm update; the parent step flushes inline
    # protocol deliveries after all deferred work completes.
    deferred_apply =
      fn state, target, message, message_value, source, trigger ->
        StepApply.apply(
          state,
          target,
          message,
          message_value,
          source,
          trigger,
          [],
          step_apply
        )
      end

    apply_step_once =
      fn state, target, message, message_value, source, trigger ->
        StepDepth.enter()

        state =
          state
          |> StepApply.apply(
            target,
            message,
            message_value,
            source,
            trigger,
            [],
            step_apply
          )
          |> Ide.Debugger.CompanionBridge.Runtime.flush_deferred_steps(%{
            companion_bridge
            | apply_step: deferred_apply
          })

        if StepDepth.leave() == 0 do
          ProtocolRx.flush_inline_protocol_deliveries(state, protocol_rx)
        else
          state
        end
      end

    host =
      Map.merge(host, %{
        apply_step_once: apply_step_once,
        apply_step_without_value: fn st, target, message, source, trigger ->
          apply_step_once.(st, target, message, nil, source, trigger)
        end
      })

    ctx = RuntimeContexts.build(host)

    %{ctx | companion_bridge: %{Map.fetch!(ctx, :companion_bridge) | apply_step: deferred_apply}}
  end

  @spec trigger_message_for_surface(
          config(),
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          String.t() | nil
        ) :: String.t()
  def trigger_message_for_surface(
        %{append_event: _} = config,
        state,
        target,
        trigger,
        requested_message
      ) do
    trigger_message_for_surface(contexts(config), state, target, trigger, requested_message)
  end

  @spec trigger_message_for_surface(
          RuntimeContexts.t(),
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          String.t() | nil
        ) :: String.t()
  def trigger_message_for_surface(
        %{step_apply: _} = ctx,
        state,
        target,
        trigger,
        requested_message
      ) do
    context_trigger_message({:built, ctx}, state, target, trigger, requested_message)
  end

  @spec tick_message_for_surface(config(), Types.runtime_state(), Types.surface_target()) ::
          String.t()
  def tick_message_for_surface(%{append_event: _} = config, state, target) when is_map(state) do
    tick_message_for_surface(contexts(config), state, target)
  end

  @spec tick_message_for_surface(
          RuntimeContexts.t(),
          Types.runtime_state(),
          Types.surface_target()
        ) ::
          String.t()
  def tick_message_for_surface(%{step_apply: _} = ctx, state, target) when is_map(state) do
    TriggerSurface.tick_message(state, target, ctx.tick_resolution)
  end

  @spec attach_subscription_payload(
          config(),
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          String.t()
        ) :: String.t()
  def attach_subscription_payload(%{append_event: _} = config, state, target, message, trigger) do
    attach_subscription_payload(contexts(config), state, target, message, trigger)
  end

  @spec attach_subscription_payload(
          RuntimeContexts.t(),
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          String.t()
        ) :: String.t()
  def attach_subscription_payload(%{step_apply: _} = ctx, state, target, message, trigger) do
    context_attach_subscription({:built, ctx}, state, target, message, trigger)
  end

  @spec apply_subscription_ok_response(
          config(),
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          Types.subscription_payload(),
          String.t(),
          String.t()
        ) :: Types.runtime_state()
  def apply_subscription_ok_response(
        %{append_event: _} = config,
        state,
        target,
        callback,
        payload,
        source,
        trigger
      ) do
    apply_subscription_ok_response(
      contexts(config),
      state,
      target,
      callback,
      payload,
      source,
      trigger
    )
  end

  @spec apply_subscription_ok_response(
          RuntimeContexts.t(),
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          Types.subscription_payload(),
          String.t(),
          String.t()
        ) :: Types.runtime_state()
  def apply_subscription_ok_response(
        %{step_apply: _} = ctx,
        state,
        target,
        callback,
        payload,
        source,
        trigger
      ) do
    context_apply_subscription_ok(
      {:built, ctx},
      state,
      target,
      callback,
      payload,
      source,
      trigger
    )
  end

  @spec maybe_attach_compile_artifacts_for_parser_view(
          config(),
          Types.runtime_state(),
          Types.surface_target(),
          Types.elm_introspect()
        ) :: Types.runtime_state()
  def maybe_attach_compile_artifacts_for_parser_view(
        %{append_event: _} = config,
        state,
        target,
        ei
      ) do
    maybe_attach_compile_artifacts_for_parser_view(contexts(config), state, target, ei)
  end

  @spec maybe_attach_compile_artifacts_for_parser_view(
          RuntimeContexts.t(),
          Types.runtime_state(),
          Types.surface_target(),
          Types.elm_introspect()
        ) :: Types.runtime_state()
  def maybe_attach_compile_artifacts_for_parser_view(%{step_apply: _} = ctx, state, target, ei) do
    context_attach_compile_artifacts({:built, ctx}, state, target, ei)
  end

  @spec simulator_settings_from_state(Types.runtime_state()) :: Types.simulator_settings()
  def simulator_settings_from_state(state) when is_map(state),
    do: DebuggerSimulatorSettings.from_state(state)

  def simulator_settings_from_state(_state), do: DebuggerSimulatorSettings.default()

  @spec simulator_now_for_target(Types.runtime_state(), Types.surface_target()) ::
          NaiveDateTime.t()
  def simulator_now_for_target(state, target),
    do: SubscriptionPayload.simulator_now_for_target(state, target)

  @spec session_key_from_state(Types.runtime_state()) :: String.t() | nil
  def session_key_from_state(state), do: SessionDefaults.session_key_from_state(state)

  defp runtime_host_callbacks_impl(%{} = config, ctx_ref) do
    status = %{
      append_event: config.append_event,
      append_debugger_event: config.append_debugger_event,
      source_root_for_target: &SurfaceTargets.source_root/1
    }

    apply_step = apply_step_callback(config, ctx_ref)

    {trigger_message_for_surface, attach_subscription_payload} =
      subscription_wire_fns(ctx_ref)

    RuntimeHostCallbacks.build(%{
      append_event: config.append_event,
      append_debugger_event: config.append_debugger_event,
      apply_step_once: apply_step,
      apply_step_without_value: fn st, target, message, source, trigger ->
        apply_step.(st, target, message, nil, source, trigger)
      end,
      source_root_for_target: &SurfaceTargets.source_root/1,
      session_key_from_state: &session_key_from_state/1,
      simulator_settings_from_state: &simulator_settings_from_state/1,
      introspect_for: &SurfaceAccess.introspect/2,
      surface_app_model: &SurfaceAccess.app_model/2,
      normalize_step_target: &SurfaceTargets.normalize/1,
      trigger_message_for_surface: trigger_message_for_surface,
      attach_subscription_payload: attach_subscription_payload,
      merge_runtime_artifacts: &RuntimeArtifactMerge.maybe_merge/3,
      apply_subscription_ok_response: fn state, target, callback, payload, source, trigger ->
        context_apply_subscription_ok(ctx_ref, state, target, callback, payload, source, trigger)
      end,
      maybe_attach_compile_artifacts: fn state, target, ei ->
        context_attach_compile_artifacts(ctx_ref, state, target, ei)
      end,
      maybe_append_runtime_status: fn state, target ->
        RuntimeStatusFacades.maybe_append_simple_status(status, state, target)
      end,
      maybe_append_runtime_status_after_init: fn state, target, execution, introspect ->
        RuntimeStatusFacades.maybe_append_after_execution(
          status,
          state,
          target,
          execution,
          introspect
        )
      end,
      maybe_append_contract: fn state, payload ->
        RuntimeStatusFacades.maybe_append_contract(status, state, payload)
      end,
      maybe_append_runtime_exec: fn state, source_root ->
        RuntimeStatusFacades.maybe_append_runtime_exec(status, state, source_root)
      end,
      maybe_append_phone_view_render: fn state, root ->
        HotReloadSurface.maybe_append_phone_view_render(state, root, config.append_event)
      end,
      append_runtime_exec: fn state, target, extra ->
        RuntimeStatusFacades.append_runtime_exec_for_target(status, state, target, extra)
      end,
      simulator_now: &simulator_now_for_target/2,
      default_auto_fire_interval_ms: config.default_auto_fire_interval_ms
    })
  end

  defp apply_step_callback(_config, :stub) do
    fn state, _target, _message, _message_value, _source, _trigger ->
      state
    end
  end

  defp apply_step_callback(_config, {:built, %{step_apply: step_apply}}) do
    fn state, target, message, message_value, source, trigger ->
      StepApply.apply(state, target, message, message_value, source, trigger, [], step_apply)
    end
  end

  # Built callbacks must not use stub_ctx.tick_resolution: the stub pass wires
  # attach_payload to a no-op, which makes auto-fire resolve "" and cycle Msg
  # constructors (CurrentDateTime before MinuteChanged) instead of the subscription row.
  @spec subscription_wire_fns(:stub | {:built, RuntimeContexts.t()}) ::
          {(Types.runtime_state(), Types.surface_target(), String.t(), String.t() | nil ->
              String.t()),
           (Types.runtime_state(), Types.surface_target(), String.t(), String.t() -> String.t())}
  defp subscription_wire_fns(:stub) do
    {fn _, _, _, _ -> "" end, fn _, _, message, _ -> message end}
  end

  defp subscription_wire_fns({:built, _stub_ctx}) do
    payload_ctx = %{
      introspect: &SurfaceAccess.introspect/2,
      settings: &simulator_settings_from_state/1
    }

    tick_resolution = %{
      introspect_for: &SurfaceAccess.introspect/2,
      attach_payload: fn state, target, message, trigger ->
        TriggerMessageSurface.attach_payload(state, target, message, trigger, payload_ctx)
      end
    }

    {
      fn state, target, trigger, requested_message ->
        TriggerSurface.trigger_message(state, target, trigger, requested_message, tick_resolution)
      end,
      fn state, target, message, trigger ->
        TriggerMessageSurface.attach_payload(state, target, message, trigger, payload_ctx)
      end
    }
  end

  defp context_trigger_message(
         {:built, %{tick_resolution: tick_resolution}},
         state,
         target,
         trigger,
         requested_message
       ) do
    TriggerSurface.trigger_message(state, target, trigger, requested_message, tick_resolution)
  end

  defp context_attach_subscription(
         {:built, %{subscription_payload: subscription_payload}},
         state,
         target,
         message,
         trigger
       ) do
    TriggerMessageSurface.attach_payload(state, target, message, trigger, subscription_payload)
  end

  defp context_apply_subscription_ok(
         :stub,
         state,
         _target,
         _callback,
         _payload,
         _source,
         _trigger
       ),
       do: state

  defp context_apply_subscription_ok(
         {:built, %{subscription_responses: subscription_responses}},
         state,
         target,
         callback,
         payload,
         source,
         trigger
       ) do
    SubscriptionResponses.apply_ok(
      state,
      target,
      callback,
      payload,
      source,
      trigger,
      subscription_responses
    )
  end

  defp context_attach_compile_artifacts(:stub, state, _target, _ei), do: state

  defp context_attach_compile_artifacts(
         {:built, %{surface_compile: surface_compile}},
         state,
         target,
         _ei
       ) do
    SurfaceCompileArtifacts.maybe_attach_for_parser_view(state, target, surface_compile)
  end
end
