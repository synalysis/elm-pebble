defmodule Ide.Debugger.HttpFlightCommit do
  @moduledoc false

  alias Ide.Debugger.PendingHttpFollowups
  alias Ide.Debugger.PendingProtocolDelivery
  alias Ide.Debugger.Types

  @surfaces [:watch, :companion, :phone]

  @spec commit(
          Types.runtime_state(),
          Types.runtime_state(),
          Types.runtime_state(),
          Types.surface_target()
        ) :: Types.runtime_state()
  def commit(current, applied, basis, target)
      when is_map(current) and is_map(applied) and is_map(basis) and
             target in @surfaces do
    basis_dbg = dbg_seq(basis)
    basis_seq = session_seq(basis)

    new_timeline =
      applied
      |> Map.get(:debugger_timeline, [])
      |> Enum.filter(fn row -> row_dbg_seq(row) > basis_dbg end)

    new_events =
      applied
      |> Map.get(:events, [])
      |> Enum.filter(fn event -> session_seq(event) > basis_seq end)

    current
    |> Map.put(target, Map.get(applied, target))
    |> Map.put(
      :pending_http_followups,
      merge_pending_items(
        PendingHttpFollowups.pending(current),
        PendingHttpFollowups.pending(applied),
        PendingHttpFollowups.pending(basis)
      )
    )
    |> Map.put(
      :pending_protocol_deliveries,
      merge_pending_items(
        PendingProtocolDelivery.pending(current),
        PendingProtocolDelivery.pending(applied),
        PendingProtocolDelivery.pending(basis)
      )
    )
    |> Map.put(:app_message_queues, merge_app_message_queues(current, applied, basis))
    |> Map.update(:debugger_timeline, new_timeline, &(new_timeline ++ &1))
    |> Map.update(:events, new_events, &(new_events ++ &1))
    |> Map.put(:debugger_seq, max(dbg_seq(current), dbg_seq(applied)))
    |> Map.put(:seq, max(session_seq(current), session_seq(applied)))
  end

  defp merge_pending_items(current_items, applied_items, basis_items)
       when is_list(current_items) and is_list(applied_items) and is_list(basis_items) do
    new_items = Enum.drop(applied_items, length(basis_items))
    current_items ++ new_items
  end

  defp merge_app_message_queues(current, applied, basis) do
    current_q = Map.get(current, :app_message_queues, %{})
    applied_q = Map.get(applied, :app_message_queues, %{})
    basis_q = Map.get(basis, :app_message_queues, %{})

    Enum.reduce(@surfaces, current_q, fn surface, acc ->
      applied_val = queue_for(applied_q, surface)
      basis_val = queue_for(basis_q, surface)
      current_val = queue_for(acc, surface)

      Map.put(acc, surface, if(applied_val != basis_val, do: applied_val, else: current_val))
    end)
  end

  defp queue_for(queues, surface) when is_map(queues) do
    Map.get(queues, surface) || Map.get(queues, Atom.to_string(surface)) || []
  end

  defp dbg_seq(state) when is_map(state) do
    Map.get(state, :debugger_seq) || Map.get(state, "debugger_seq", 0)
  end

  defp row_dbg_seq(%{seq: seq}) when is_integer(seq), do: seq
  defp row_dbg_seq(row) when is_map(row), do: Map.get(row, "seq", 0)
  defp row_dbg_seq(_), do: 0

  defp session_seq(%{seq: seq}) when is_integer(seq), do: seq
  defp session_seq(state) when is_map(state), do: Map.get(state, :seq, 0)
  defp session_seq(_), do: 0
end
