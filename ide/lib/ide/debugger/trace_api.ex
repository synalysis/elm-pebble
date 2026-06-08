defmodule Ide.Debugger.TraceApi do
  @moduledoc false

  alias Ide.Debugger.AgentSession
  alias Ide.Debugger.ReplayRecent
  alias Ide.Debugger.SnapshotContinueSession
  alias Ide.Debugger.SnapshotReference
  alias Ide.Debugger.TraceExchangeSession
  alias Ide.Debugger.Types

  @type runtime_state :: Types.RuntimeState.t() | Types.RuntimeState.wire_map()
  @type runtime_event :: Types.runtime_event()

  @spec replay_recent(String.t(), Types.replay_attrs()) :: {:ok, runtime_state()}
  def replay_recent(project_slug, attrs \\ %{}) when is_binary(project_slug) and is_map(attrs) do
    AgentSession.with_hosts(fn hosts ->
      AgentSession.mutate(project_slug, &ReplayRecent.apply(&1, attrs, hosts.replay_recent))
    end)
  end

  @spec continue_from_snapshot(String.t(), Types.snapshot_continue_attrs()) ::
          {:ok, runtime_state()}
  def continue_from_snapshot(project_slug, attrs \\ %{})
      when is_binary(project_slug) and is_map(attrs) do
    AgentSession.with_hosts(fn hosts ->
      AgentSession.mutate(project_slug, fn state ->
        SnapshotContinueSession.apply(state, attrs, hosts.append_event)
      end)
    end)
  end

  @spec snapshot_reference_rows([runtime_event()]) :: [Types.wire_map()]
  def snapshot_reference_rows(events), do: SnapshotReference.rows(events)

  @spec export_trace(String.t(), Types.export_trace_opts()) :: {:ok, Types.export_trace_result()}
  def export_trace(project_slug, opts \\ []) when is_binary(project_slug) do
    AgentSession.with_hosts(fn hosts ->
      TraceExchangeSession.export(project_slug, opts, hosts.trace_export)
    end)
  end

  @spec import_trace(String.t(), Types.import_trace_input(), keyword()) ::
          {:ok, runtime_state()}
          | {:error, Types.protocol_error() | atom() | String.t() | Types.wire_map()}
  def import_trace(session_key, input, opts \\ []) when is_binary(session_key) do
    AgentSession.with_hosts(fn hosts ->
      TraceExchangeSession.import(session_key, input, opts, hosts.trace_import)
    end)
  end

  @spec snapshot(String.t(), Types.snapshot_opts()) :: {:ok, runtime_state()}
  def snapshot(project_slug, opts \\ []) when is_binary(project_slug) do
    {:ok, AgentSession.snapshot(project_slug, opts)}
  end
end
