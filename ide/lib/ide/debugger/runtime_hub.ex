defmodule Ide.Debugger.RuntimeHub do
  @moduledoc false

  alias Ide.Debugger.HotReloadSurface
  alias Ide.Debugger.OperationHosts
  alias Ide.Debugger.RuntimeArtifactMerge
  alias Ide.Debugger.RuntimeContexts
  alias Ide.Debugger.RuntimeHost
  alias Ide.Debugger.RuntimeHostCallbacks
  alias Ide.Debugger.RuntimeStatusFacades
  alias Ide.Debugger.SessionDefaults
  alias Ide.Debugger.SimulatorSettings, as: DebuggerSimulatorSettings
  alias Ide.Debugger.StepApply
  alias Ide.Debugger.SubscriptionPayload
  alias Ide.Debugger.SubscriptionResponses
  alias Ide.Debugger.SurfaceAccess
  alias Ide.Debugger.SurfaceCompileArtifacts
  alias Ide.Debugger.SurfaceTargets
  alias Ide.Debugger.TriggerMessageSurface
  alias Ide.Debugger.TriggerSurface
  alias Ide.Debugger.Types

  @type append_event_fn :: (Types.runtime_state(), String.t(), map() -> Types.runtime_state())

  @type append_debugger_event_fn ::
          (Types.runtime_state(), String.t(), Types.surface_target(), String.t(), String.t() ->
             Types.runtime_state())

  @type update_fn ::
          (String.t(), (Types.runtime_state() -> Types.runtime_state()) -> {:ok, Types.runtime_state()})

  @type config :: %{
          required(:append_event) => append_event_fn(),
          required(:append_debugger_event) => append_debugger_event_fn(),
          required(:update) => update_fn(),
          required(:default_auto_fire_interval_ms) => pos_integer()
        }

  @spec contexts(config()) :: RuntimeContexts.t()
  def contexts(%{} = config) do
    RuntimeContexts.build(RuntimeHost.build(runtime_host_callbacks(config)))
  end

  @spec operation_deps(config()) :: OperationHosts.deps()
  def operation_deps(%{} = config) do
    %{
      apply_step_once: fn st, target, message, message_value, source, trigger ->
        apply_step_once(config, st, target, message, message_value, source, trigger, [])
      end,
      append_event: config.append_event,
      normalize_target: &SurfaceTargets.normalize/1,
      replay_label: &SurfaceTargets.replay_label/1,
      source_root_for_target: &SurfaceTargets.source_root/1,
      tick_message_for_surface: fn state, target ->
        tick_message_for_surface(config, state, target)
      end,
      update: config.update,
      contexts: fn -> contexts(config) end,
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
  def apply_step_once(config, state, target, requested_message, message_value, source_override, trigger, opts)
      when target in [:watch, :companion, :phone] and is_list(opts) do
    StepApply.apply(
      state,
      target,
      requested_message,
      message_value,
      source_override,
      trigger,
      opts,
      contexts(config).step_apply
    )
  end

  @spec trigger_message_for_surface(
          config(),
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          String.t() | nil
        ) :: String.t()
  def trigger_message_for_surface(config, state, target, trigger, requested_message) do
    TriggerSurface.trigger_message(
      state,
      target,
      trigger,
      requested_message,
      contexts(config).tick_resolution
    )
  end

  @spec tick_message_for_surface(config(), Types.runtime_state(), Types.surface_target()) :: String.t()
  def tick_message_for_surface(config, state, target) when is_map(state) do
    TriggerSurface.tick_message(state, target, contexts(config).tick_resolution)
  end

  @spec attach_subscription_payload(
          config(),
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          String.t()
        ) :: String.t()
  def attach_subscription_payload(config, state, target, message, trigger) do
    TriggerMessageSurface.attach_payload(
      state,
      target,
      message,
      trigger,
      contexts(config).subscription_payload
    )
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
  def apply_subscription_ok_response(config, state, target, callback, payload, source, trigger) do
    SubscriptionResponses.apply_ok(
      state,
      target,
      callback,
      payload,
      source,
      trigger,
      contexts(config).subscription_responses
    )
  end

  @spec maybe_attach_compile_artifacts_for_parser_view(
          config(),
          Types.runtime_state(),
          Types.surface_target(),
          map()
        ) :: Types.runtime_state()
  def maybe_attach_compile_artifacts_for_parser_view(config, state, target, _ei) do
    SurfaceCompileArtifacts.maybe_attach_for_parser_view(state, target, contexts(config).surface_compile)
  end

  @spec simulator_settings_from_state(Types.runtime_state()) :: Types.simulator_settings()
  def simulator_settings_from_state(state) when is_map(state),
    do: DebuggerSimulatorSettings.from_state(state)

  def simulator_settings_from_state(_state), do: DebuggerSimulatorSettings.default()

  @spec simulator_now_for_target(Types.runtime_state(), Types.surface_target()) :: NaiveDateTime.t()
  def simulator_now_for_target(state, target),
    do: SubscriptionPayload.simulator_now_for_target(state, target)

  @spec session_key_from_state(Types.runtime_state()) :: String.t() | nil
  def session_key_from_state(state), do: SessionDefaults.session_key_from_state(state)

  defp runtime_host_callbacks(%{} = config) do
    status = %{
      append_event: config.append_event,
      append_debugger_event: config.append_debugger_event,
      source_root_for_target: &SurfaceTargets.source_root/1
    }

    RuntimeHostCallbacks.build(%{
      append_event: config.append_event,
      append_debugger_event: config.append_debugger_event,
      apply_step_once: fn st, target, message, message_value, source, trigger ->
        apply_step_once(config, st, target, message, message_value, source, trigger, [])
      end,
      apply_step_without_value: fn st, target, message, source, trigger ->
        apply_step_once(config, st, target, message, nil, source, trigger, [])
      end,
      source_root_for_target: &SurfaceTargets.source_root/1,
      session_key_from_state: &session_key_from_state/1,
      simulator_settings_from_state: &simulator_settings_from_state/1,
      introspect_for: &SurfaceAccess.introspect/2,
      surface_app_model: &SurfaceAccess.app_model/2,
      normalize_step_target: &SurfaceTargets.normalize/1,
      trigger_message_for_surface: fn state, target, trigger, requested_message ->
        trigger_message_for_surface(config, state, target, trigger, requested_message)
      end,
      attach_subscription_payload: fn state, target, message, trigger ->
        attach_subscription_payload(config, state, target, message, trigger)
      end,
      merge_runtime_artifacts: &RuntimeArtifactMerge.maybe_merge/3,
      apply_subscription_ok_response: fn state, target, callback, payload, source, trigger ->
        apply_subscription_ok_response(config, state, target, callback, payload, source, trigger)
      end,
      maybe_attach_compile_artifacts: fn state, target, ei ->
        maybe_attach_compile_artifacts_for_parser_view(config, state, target, ei)
      end,
      maybe_append_runtime_status: fn state, target ->
        RuntimeStatusFacades.maybe_append_simple_status(status, state, target)
      end,
      maybe_append_runtime_status_after_init: fn state, target, execution, introspect ->
        RuntimeStatusFacades.maybe_append_after_execution(status, state, target, execution, introspect)
      end,
      maybe_append_elm_introspect: fn state, payload ->
        RuntimeStatusFacades.maybe_append_elm_introspect(status, state, payload)
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
end
