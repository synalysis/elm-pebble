defmodule Ide.Debugger.AgentSession do
  @moduledoc false

  alias Ide.Debugger.AgentHosts
  alias Ide.Debugger.AgentStore
  alias Ide.Debugger.CompileIngestApply
  alias Ide.Debugger.EventLog
  alias Ide.Debugger.SessionDefaults
  alias Ide.Debugger.SnapshotQuery
  alias Ide.Debugger.SurfaceTargets
  alias Ide.Debugger.Types

  @history_limit 500
  @default_auto_fire_interval_ms 1_000
  @agent_call_timeout_ms 30_000

  @type runtime_state :: Types.RuntimeState.t() | Types.RuntimeState.wire_map()

  @spec history_limit() :: pos_integer()
  def history_limit, do: @history_limit

  @spec mutate(String.t(), (runtime_state() -> runtime_state())) :: {:ok, runtime_state()}
  def mutate(project_slug, updater) when is_binary(project_slug) and is_function(updater, 1) do
    AgentStore.update(project_slug, updater, timeout: @agent_call_timeout_ms)
  end

  @spec snapshot(String.t(), Types.snapshot_opts()) :: runtime_state()
  def snapshot(project_slug, opts \\ []) when is_binary(project_slug) do
    SnapshotQuery.fetch(project_slug, opts, hosts().snapshot_query)
  end

  @spec with_hosts((AgentHosts.t() -> term())) :: term()
  def with_hosts(fun) when is_function(fun, 1), do: fun.(hosts())

  @spec mutate_ingest(
          String.t(),
          (Types.runtime_state(), CompileIngestApply.host() -> Types.runtime_state())
        ) :: {:ok, runtime_state()}
  def mutate_ingest(project_slug, apply_fun)
      when is_binary(project_slug) and is_function(apply_fun, 2) do
    with_hosts(fn hosts -> mutate(project_slug, &apply_fun.(&1, hosts.compile_ingest)) end)
  end

  @spec hosts() :: AgentHosts.t()
  def hosts do
    AgentHosts.build(
      history_limit: @history_limit,
      default_auto_fire_interval_ms: @default_auto_fire_interval_ms,
      append_event: &append_event/3,
      append_debugger_event: &append_debugger_event/5,
      update: &mutate/2,
      ensure_phone_state: &SessionDefaults.ensure_phone_state/1,
      human_slug_from_session_key: &SessionDefaults.human_slug_from_session_key/1
    )
  end

  @spec append_event(runtime_state(), String.t(), map()) :: runtime_state()
  def append_event(state, type, payload) when is_map(state) do
    EventLog.append(state, type, payload, limit: @history_limit)
  end

  @spec append_debugger_event(
          runtime_state(),
          String.t(),
          Types.surface_target(),
          String.t(),
          String.t()
        ) :: runtime_state()
  def append_debugger_event(state, type, target, message, message_source) when is_map(state) do
    EventLog.append_debugger_event(state, type, target, message, message_source,
      limit: @history_limit,
      source_root_for_target: &SurfaceTargets.source_root/1
    )
  end
end
