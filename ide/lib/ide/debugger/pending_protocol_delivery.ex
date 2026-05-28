defmodule Ide.Debugger.PendingProtocolDelivery do
  @moduledoc """
  Applies deferred AppMessage (`debugger.protocol_rx`) subscription delivery outside
  the sender's Agent mutate.

  Deliveries run sequentially in a background task (FIFO), matching typical transport
  ordering per recipient while letting the watch (or phone) mutate return immediately.
  """

  alias Ide.Debugger.AgentHosts
  alias Ide.Debugger.AgentSession
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.RuntimeBackgroundDrains
  alias Ide.Debugger.RuntimeBackgroundNotify
  alias Ide.Debugger.RuntimeBackgroundWork

  @pending_key :pending_protocol_deliveries

  @spec async?() :: boolean()
  def async? do
    Application.get_env(:ide, :debugger_async_protocol_delivery, true)
  end

  @spec maybe_schedule_drain(String.t(), map()) :: :ok
  def maybe_schedule_drain(project_slug, state)
      when is_binary(project_slug) and is_map(state) do
    if async?() do
      items = pending(state)

      if items != [] do
        {:ok, _} =
          AgentSession.mutate(project_slug, fn st ->
            put_pending(st, [])
          end)

        hosts = AgentSession.hosts()
        ctx = hosts |> AgentHosts.contexts() |> Map.fetch!(:protocol_rx)

        RuntimeBackgroundWork.spawn(project_slug, fn ->
          run_drain_batch(project_slug, items, ctx)
        end)
      end
    end

    :ok
  end

  @spec pending(map()) :: [map()]
  def pending(state) when is_map(state) do
    case Map.get(state, @pending_key) || Map.get(state, to_string(@pending_key)) do
      items when is_list(items) -> items
      _ -> legacy_companion_pending(state)
    end
  end

  @spec enqueue(map(), :watch | :companion | :phone, map()) :: map()
  def enqueue(state, recipient, payload)
      when is_map(state) and recipient in [:watch, :companion, :phone] and is_map(payload) do
    item = %{
      "recipient" => Atom.to_string(recipient),
      "payload" => payload
    }

    Map.update(state, @pending_key, [item], &(&1 ++ [item]))
  end

  @spec run_drain_batch(String.t(), [map()], ProtocolRx.ctx()) :: :ok
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
end
