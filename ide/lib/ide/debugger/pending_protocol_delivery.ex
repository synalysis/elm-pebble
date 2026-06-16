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

      case :ets.lookup(@drain_lock_table, project_slug) do
        [{^project_slug, true}] ->
          :ok

        _ ->
          :ets.insert(@drain_lock_table, {project_slug, true})

          hosts = AgentSession.hosts()
          ctx = hosts |> AgentHosts.contexts() |> Map.fetch!(:protocol_rx)

          RuntimeBackgroundWork.spawn(project_slug, fn ->
            try do
              drain_until_empty(project_slug, ctx)
            after
              :ets.delete(@drain_lock_table, project_slug)

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

  defp drain_until_empty(project_slug, ctx)
       when is_binary(project_slug) and is_map(ctx) do
    items = project_slug |> AgentStore.fetch() |> pending()

    if items != [] do
      {:ok, _} =
        AgentSession.mutate(project_slug, fn st ->
          put_pending(st, [])
        end)

      run_drain_batch(project_slug, items, ctx)
      drain_until_empty(project_slug, ctx)
    else
      :ok
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

  defp delivery_fields(item) when is_map(item) do
    recipient =
      item
      |> Map.get("recipient")
      |> normalize_recipient()

    payload = Map.get(item, "payload") || %{}
    {recipient, payload}
  end

  defp normalize_recipient("watch"), do: :watch
  defp normalize_recipient("companion"), do: :companion
  defp normalize_recipient("phone"), do: :phone
  defp normalize_recipient(_), do: :companion

  defp put_pending(state, items) when is_map(state) and is_list(items) do
    state
    |> Map.put(@pending_key, items)
    |> drop_legacy_companion_pending()
  end

  defp legacy_companion_pending(state) do
    case Map.get(state, :companion) do
      %{@pending_key => items} when is_list(items) -> items
      _ -> []
    end
  end

  defp drop_legacy_companion_pending(state) do
    update_in(state, [:companion], fn
      %{@pending_key => _} = companion -> Map.delete(companion, @pending_key)
      other -> other
    end)
  end

  defp ensure_drain_lock_table do
    if :ets.whereis(@drain_lock_table) == :undefined do
      :ets.new(@drain_lock_table, [:named_table, :public, :set, read_concurrency: true])
    end

    :ok
  end
end
