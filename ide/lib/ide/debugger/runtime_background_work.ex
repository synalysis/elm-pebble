defmodule Ide.Debugger.RuntimeBackgroundWork do
  @moduledoc """
  Tracks in-flight debugger background tasks (async HTTP, deferred AppMessage delivery)
  and supports waiting until queues are drained.
  """

  alias Ide.Debugger.AgentStore
  alias Ide.Debugger.PendingHttpFollowups
  alias Ide.Debugger.PendingProtocolDelivery
  alias Ide.Debugger.RuntimeBackgroundNotify

  @table :debugger_background_inflight
  @default_await_timeout_ms 120_000

  @spec spawn(String.t(), (-> :ok)) :: :ok
  def spawn(project_slug, fun) when is_binary(project_slug) and is_function(fun, 0) do
    inc(project_slug)

    Task.start(fn ->
      try do
        fun.()
      after
        dec(project_slug)
        RuntimeBackgroundNotify.broadcast(project_slug)
      end
    end)

    :ok
  end

  @spec await_idle(String.t(), timeout()) :: :ok | :timeout
  def await_idle(project_slug, timeout \\ @default_await_timeout_ms)
      when is_binary(project_slug) and is_integer(timeout) and timeout > 0 do
    deadline = System.monotonic_time(:millisecond) + timeout

    if poll_idle(project_slug, deadline), do: :ok, else: :timeout
  end

  @spec idle?(String.t()) :: boolean()
  def idle?(project_slug) when is_binary(project_slug) do
    if inflight?(project_slug) do
      false
    else
      state = AgentStore.fetch(project_slug, timeout: 5_000)

      PendingHttpFollowups.pending(state) == [] and
        PendingProtocolDelivery.pending(state) == []
    end
  rescue
    _ -> false
  end

  @spec inc(String.t()) :: non_neg_integer()
  def inc(project_slug) when is_binary(project_slug) do
    ensure_table()
    :ets.update_counter(@table, project_slug, 1, {:default, 0})
  end

  @spec dec(String.t()) :: non_neg_integer()
  def dec(project_slug) when is_binary(project_slug) do
    ensure_table()
    :ets.update_counter(@table, project_slug, -1, {:default, 0})
  end

  @spec inflight?(String.t()) :: boolean()
  def inflight?(project_slug) when is_binary(project_slug) do
    ensure_table()

    case :ets.lookup(@table, project_slug) do
      [{^project_slug, count}] when is_integer(count) and count > 0 -> true
      _ -> false
    end
  end

  defp poll_idle(project_slug, deadline) do
    if idle?(project_slug) do
      true
    else
      if System.monotonic_time(:millisecond) > deadline do
        false
      else
        Process.sleep(25)
        poll_idle(project_slug, deadline)
      end
    end
  end

  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    end

    :ok
  end
end
