defmodule Ide.Debugger.AgentHosts do
  @moduledoc false

  alias Ide.Debugger.AgentStore
  alias Ide.Debugger.CompileIngestApply
  alias Ide.Debugger.ConfigurationReload
  alias Ide.Debugger.ConfigurationSession
  alias Ide.Debugger.DebuggerStep
  alias Ide.Debugger.HotReloadSession
  alias Ide.Debugger.OperationHosts
  alias Ide.Debugger.ReplayRecent
  alias Ide.Debugger.RuntimeContexts
  alias Ide.Debugger.RuntimeHub
  alias Ide.Debugger.SessionStartReset
  alias Ide.Debugger.SimulatorSettingsApply
  alias Ide.Debugger.SnapshotQuery
  alias Ide.Debugger.SubscriptionToggle
  alias Ide.Debugger.TickIngress
  alias Ide.Debugger.TraceExchangeSession
  alias Ide.Debugger.TriggerDiscovery
  alias Ide.Debugger.TriggerInjectionSession
  alias Ide.Debugger.Types
  alias Ide.Debugger.WatchProfileApply

  @type append_event_fn ::
          (Types.runtime_state(), String.t(), Types.debugger_timeline_payload() ->
             Types.runtime_state())

  @type append_debugger_event_fn ::
          (Types.runtime_state(), String.t(), Types.surface_target(), String.t(), String.t() ->
             Types.runtime_state())

  @type update_fn ::
          (String.t(), (Types.runtime_state() -> Types.runtime_state()) ->
             {:ok, Types.runtime_state()})

  @type ensure_phone_fn :: (Types.runtime_state() -> Types.runtime_state())

  @type human_slug_fn :: (String.t() -> String.t())

  @type build_opts :: [
          history_limit: pos_integer(),
          default_auto_fire_interval_ms: pos_integer(),
          append_event: append_event_fn(),
          append_debugger_event: append_debugger_event_fn(),
          update: update_fn(),
          ensure_phone_state: ensure_phone_fn(),
          human_slug_from_session_key: human_slug_fn()
        ]

  @type t :: %__MODULE__{
          history_limit: pos_integer(),
          hub: RuntimeHub.config(),
          operation_deps: OperationHosts.deps(),
          lifecycle: SessionStartReset.host(),
          watch_profile: WatchProfileApply.host(),
          step: DebuggerStep.host(),
          configuration_session: ConfigurationSession.host(),
          configuration_reload: ConfigurationReload.host(),
          hot_reload: HotReloadSession.host(),
          trigger_injection: TriggerInjectionSession.host(),
          trigger_discovery: TriggerDiscovery.host(),
          append_event: append_event_fn(),
          compile_ingest: CompileIngestApply.host(),
          replay_recent: ReplayRecent.host(),
          subscription_toggle: SubscriptionToggle.host(),
          tick_ingress: TickIngress.host(),
          simulator_settings: SimulatorSettingsApply.host(),
          trace_export: TraceExchangeSession.export_host(),
          trace_import: TraceExchangeSession.import_host(),
          snapshot_query: SnapshotQuery.host()
        }

  defstruct [
    :history_limit,
    :hub,
    :operation_deps,
    :lifecycle,
    :watch_profile,
    :step,
    :configuration_session,
    :configuration_reload,
    :hot_reload,
    :trigger_injection,
    :trigger_discovery,
    :append_event,
    :compile_ingest,
    :replay_recent,
    :subscription_toggle,
    :tick_ingress,
    :simulator_settings,
    :trace_export,
    :trace_import,
    :snapshot_query
  ]

  @spec build(build_opts()) :: t()
  def build(opts) when is_list(opts) do
    hub = %{
      append_event: Keyword.fetch!(opts, :append_event),
      append_debugger_event: Keyword.fetch!(opts, :append_debugger_event),
      update: Keyword.fetch!(opts, :update),
      default_auto_fire_interval_ms: Keyword.fetch!(opts, :default_auto_fire_interval_ms)
    }

    operation_deps = RuntimeHub.operation_deps(hub)
    ensure_phone = Keyword.fetch!(opts, :ensure_phone_state)
    append_event = Keyword.fetch!(opts, :append_event)
    human_slug = Keyword.fetch!(opts, :human_slug_from_session_key)
    history_limit = Keyword.fetch!(opts, :history_limit)

    %__MODULE__{
      history_limit: history_limit,
      hub: hub,
      operation_deps: operation_deps,
      lifecycle: %{append_event: append_event, ensure_phone_state: ensure_phone},
      watch_profile: %{
        append_event: append_event,
        ensure_phone_state: ensure_phone,
        contexts: fn -> RuntimeHub.contexts(hub) end
      },
      step: %{
        apply_step_once: fn st, target, message, message_value, source, trigger ->
          RuntimeHub.apply_step_once(hub, st, target, message, message_value, source, trigger, [])
        end,
        normalize_target: &Ide.Debugger.SurfaceTargets.normalize/1
      },
      configuration_session: %{
        apply_step_once: fn st, target, message, message_value, source, trigger ->
          RuntimeHub.apply_step_once(hub, st, target, message, message_value, source, trigger, [])
        end,
        ensure_phone_state: ensure_phone,
        contexts: fn -> RuntimeHub.contexts(hub) end
      },
      configuration_reload: %{ensure_phone_state: ensure_phone},
      hot_reload: %{
        ensure_phone_state: ensure_phone,
        contexts: fn -> RuntimeHub.contexts(hub) end
      },
      trigger_injection: %{contexts: fn -> RuntimeHub.contexts(hub) end},
      trigger_discovery: %{trigger_surface: fn -> RuntimeHub.contexts(hub).trigger_surface end},
      append_event: append_event,
      compile_ingest: OperationHosts.compile_ingest(operation_deps),
      replay_recent: OperationHosts.replay_recent(operation_deps),
      subscription_toggle: OperationHosts.subscription_toggle(operation_deps),
      tick_ingress: OperationHosts.tick_ingress(operation_deps),
      simulator_settings: OperationHosts.simulator_settings(operation_deps),
      trace_export: %{
        snapshot: fn slug, snapshot_opts ->
          {:ok, SnapshotQuery.fetch(slug, snapshot_opts, %{fetch: &AgentStore.fetch/2})}
        end,
        human_slug_from_session_key: human_slug,
        history_limit: history_limit
      },
      trace_import: %{
        human_slug_from_session_key: human_slug,
        ensure_phone_state: ensure_phone,
        put_state: fn key, state, put_opts -> AgentStore.put(key, state, put_opts) end
      },
      snapshot_query: %{fetch: &AgentStore.fetch/2}
    }
  end

  @spec contexts(t()) :: RuntimeContexts.t()
  def contexts(%__MODULE__{hub: hub}), do: RuntimeHub.contexts(hub)
end
