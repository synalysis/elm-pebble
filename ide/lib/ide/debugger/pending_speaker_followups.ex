defmodule Ide.Debugger.PendingSpeakerFollowups do
  @moduledoc false

  alias Ide.Debugger.AgentHosts
  alias Ide.Debugger.AgentSession
  alias Ide.Debugger.RuntimeBackgroundWork
  alias Ide.Debugger.SimulatorWatchDelivery
  alias Ide.Debugger.Types

  @pending_key :pending_speaker_finished_ms
  @drain_lock_table :debugger_speaker_drain_lock

  @spec maybe_schedule(String.t(), Types.runtime_state()) :: :ok
  def maybe_schedule(project_slug, state)
      when is_binary(project_slug) and is_map(state) do
    case Map.get(state, @pending_key) do
      duration_ms when is_integer(duration_ms) and duration_ms > 0 ->
        ensure_drain_lock_table()

        case :ets.lookup(@drain_lock_table, project_slug) do
          [{^project_slug, true}] ->
            :ets.insert(@drain_lock_table, {project_slug, {:extend, duration_ms}})

          [{^project_slug, {:extend, _}}] ->
            :ets.insert(@drain_lock_table, {project_slug, {:extend, duration_ms}})

          _ ->
            start_worker(project_slug, duration_ms)
        end

      _ ->
        :ok
    end
  end

  @spec clear_pending(Types.runtime_state()) :: Types.runtime_state()
  def clear_pending(state) when is_map(state), do: Map.delete(state, @pending_key)
  def clear_pending(state), do: state

  defp inject_speaker_finished(project_slug) when is_binary(project_slug) do
    AgentSession.with_hosts(fn hosts ->
      contexts = AgentHosts.contexts(hosts)
      delivery_ctx = Map.fetch!(contexts, :simulator_watch_delivery)

      AgentSession.mutate(project_slug, fn state ->
        if Map.get(state, :running, false) do
          state
          |> clear_pending()
          |> SimulatorWatchDelivery.inject_speaker_finished(delivery_ctx)
        else
          clear_pending(state)
        end
      end)
    end)
  end

  defp start_worker(project_slug, duration_ms)
       when is_binary(project_slug) and is_integer(duration_ms) and duration_ms > 0 do
    :ets.insert(@drain_lock_table, {project_slug, true})
    AgentSession.mutate(project_slug, &clear_pending/1)

    RuntimeBackgroundWork.spawn(project_slug, fn ->
      Process.sleep(duration_ms)
      inject_speaker_finished(project_slug)
      finish_worker(project_slug)
    end)
  end

  defp finish_worker(project_slug) when is_binary(project_slug) do
    case :ets.lookup(@drain_lock_table, project_slug) do
      [{^project_slug, {:extend, duration_ms}}] when is_integer(duration_ms) and duration_ms > 0 ->
        start_worker(project_slug, duration_ms)

      _ ->
        release_drain_lock(project_slug)
    end
  end

  defp ensure_drain_lock_table do
    if :ets.whereis(@drain_lock_table) == :undefined do
      :ets.new(@drain_lock_table, [:named_table, :public, :set, read_concurrency: true])
    end

    :ok
  end

  defp release_drain_lock(project_slug) when is_binary(project_slug) do
    ensure_drain_lock_table()
    :ets.delete(@drain_lock_table, project_slug)
    :ok
  end
end
