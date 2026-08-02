defmodule Ide.Debugger.PendingProtocolDelivery do
  @moduledoc """
  Applies deferred AppMessage (`debugger.protocol_rx`) subscription delivery outside
  the sender's Agent mutate.

  Deliveries run sequentially in a background task (FIFO), matching typical transport
  ordering per recipient while letting the watch (or phone) mutate return immediately.
  """

  alias Ide.Debugger.AgentHosts
  alias Ide.Debugger.AgentSession
  alias Ide.Debugger.AgentStore
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.RuntimeBackgroundDrains
  alias Ide.Debugger.RuntimeBackgroundNotify
  alias Ide.Debugger.RuntimeBackgroundWork
  alias Ide.Debugger.Types

  @pending_key :pending_protocol_deliveries
  @drain_lock_table :debugger_protocol_drain_lock

  @spec async?() :: boolean()
  def async? do
    Application.get_env(:ide, :debugger_async_protocol_delivery, true)
  end

  @spec maybe_schedule_drain(String.t(), Types.runtime_state()) :: :ok
  def maybe_schedule_drain(project_slug, state)
      when is_binary(project_slug) and is_map(state) do
    if async?() and pending(state) != [] do
      ensure_drain_lock_table()

      # insert_new: only one drainer may start; concurrent schedule_all must not
      # spawn a second drain over the same pending items.
      if :ets.insert_new(@drain_lock_table, {project_slug, true}) do
        hosts = AgentSession.hosts()
        ctx = hosts |> AgentHosts.contexts() |> Map.fetch!(:protocol_rx)

        RuntimeBackgroundWork.spawn(project_slug, fn ->
          try do
            drain_until_empty(project_slug, ctx)
          after
            release_drain_lock(project_slug)

            st = AgentStore.fetch(project_slug)

            if pending(st) != [] do
              maybe_schedule_drain(project_slug, st)
            end
          end
        end)
      end
    end

    :ok
  end

  @spec drain_pending_sync(String.t(), ProtocolRx.ctx()) :: :ok
  def drain_pending_sync(project_slug, ctx)
      when is_binary(project_slug) and is_map(ctx) do
    # Safe alongside async drain: claim_pending/1 atomically takes ownership of
    # the queue so two drainers cannot deliver the same AppMessages.
    drain_until_empty(project_slug, ctx)
    :ok
  end

  @spec drain_until_empty(term(), term()) :: term()

  defp drain_until_empty(project_slug, ctx)
       when is_binary(project_slug) and is_map(ctx) do
    case claim_pending(project_slug) do
      [] ->
        :ok

      items ->
        run_drain_batch(project_slug, items, ctx)
        drain_until_empty(project_slug, ctx)
    end
  end

  # Claim must be atomic: a prior fetch+clear race let two drainers deliver the
  # same AppMessages (consecutive duplicate FromPhone timeline rows in live IDE).
  @spec claim_pending(String.t()) :: [Types.pending_protocol_delivery_item()]
  defp claim_pending(project_slug) when is_binary(project_slug) do
    parent = self()
    ref = make_ref()

    {:ok, _} =
      AgentSession.mutate(project_slug, fn st ->
        items = pending(st)
        send(parent, {ref, items})
        put_pending(st, [])
      end)

    receive do
      {^ref, items} when is_list(items) -> items
    after
      5_000 -> []
    end
  end

  @spec pending(Types.runtime_state()) :: [Types.pending_protocol_delivery_item()]
  def pending(state) when is_map(state) do
    case Map.get(state, @pending_key) || Map.get(state, to_string(@pending_key)) do
      items when is_list(items) -> items
      _ -> legacy_companion_pending(state)
    end
  end

  @spec enqueue(
          Types.runtime_state(),
          :watch | :companion | :phone,
          Types.protocol_tx_rx_payload()
        ) ::
          Types.runtime_state()
  def enqueue(state, recipient, payload)
      when is_map(state) and recipient in [:watch, :companion, :phone] and is_map(payload) do
    item = %{
      "recipient" => Atom.to_string(recipient),
      "payload" => payload
    }

    Map.update(state, @pending_key, [item], &(&1 ++ [item]))
  end

  @spec run_drain_batch(String.t(), [Types.pending_protocol_delivery_item()], ProtocolRx.ctx()) ::
          :ok
  def run_drain_batch(project_slug, items, ctx)
      when is_binary(project_slug) and is_list(items) and is_map(ctx) do
    state =
      Enum.reduce(items, :skip, fn item, _acc ->
        {_recipient, payload} = delivery_fields(item)

        {:ok, st} =
          AgentSession.mutate(project_slug, fn st ->
            ProtocolRx.deliver_payload(st, payload, ctx)
          end)

        RuntimeBackgroundNotify.broadcast(project_slug)
        st
      end)

    case state do
      :skip ->
        :ok

      st when is_map(st) ->
        RuntimeBackgroundDrains.schedule_all(project_slug, st)
        :ok
    end
  end

  @spec delivery_fields(map()) :: term()

  defp delivery_fields(item) when is_map(item) do
    recipient =
      item
      |> Map.get("recipient")
      |> normalize_recipient()

    payload = Map.get(item, "payload") || %{}
    {recipient, payload}
  end

  @spec normalize_recipient(term()) :: term()

  defp normalize_recipient("watch"), do: :watch
  defp normalize_recipient("companion"), do: :companion
  defp normalize_recipient("phone"), do: :phone
  defp normalize_recipient(_), do: :companion

  @spec put_pending(map(), list()) :: term()

  defp put_pending(state, items) when is_map(state) and is_list(items) do
    state
    |> Map.put(@pending_key, items)
    |> drop_legacy_companion_pending()
  end

  @spec legacy_companion_pending(term()) :: term()

  defp legacy_companion_pending(state) do
    case Map.get(state, :companion) do
      %{@pending_key => items} when is_list(items) -> items
      _ -> []
    end
  end

  @spec drop_legacy_companion_pending(term()) :: term()

  defp drop_legacy_companion_pending(state) do
    update_in(state, [:companion], fn
      %{@pending_key => _} = companion -> Map.delete(companion, @pending_key)
      other -> other
    end)
  end

  @spec ensure_drain_lock_table() :: term()

  defp ensure_drain_lock_table do
    if :ets.whereis(@drain_lock_table) == :undefined do
      :ets.new(@drain_lock_table, [:named_table, :public, :set, read_concurrency: true])
    end

    :ok
  end

  @spec release_drain_lock(String.t()) :: :ok
  defp release_drain_lock(project_slug) when is_binary(project_slug) do
    case :ets.whereis(@drain_lock_table) do
      :undefined -> :ok
      tid -> :ets.delete(tid, project_slug)
    end

    :ok
  end
end
