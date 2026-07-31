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
    current_dbg = dbg_seq(current)
    current_seq = session_seq(current)

    # HTTP flights snapshot `basis` then run unlocked. Concurrent watch auto-fire
    # can advance `current` seqs while the flight still numbers from `basis`, so
    # naive prepend would collide (duplicate debugger_seq). Renumber flight-new
    # rows to continue after `current`.
    {new_timeline, next_dbg} =
      applied
      |> Map.get(:debugger_timeline, [])
      |> Enum.filter(fn row -> row_dbg_seq(row) > basis_dbg end)
      |> renumber_rows(current_dbg)

    {new_events, next_seq} =
      applied
      |> Map.get(:events, [])
      |> Enum.filter(fn event -> session_seq(event) > basis_seq end)
      |> renumber_rows(current_seq)

    current
    |> merge_changed_surfaces(applied, basis)
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
    |> Map.put(:debugger_seq, next_dbg)
    |> Map.put(:seq, next_seq)
  end

  @spec merge_changed_surfaces(term(), term(), term()) :: term()

  defp merge_changed_surfaces(current, applied, basis)
       when is_map(current) and is_map(applied) and is_map(basis) do
    Enum.reduce(@surfaces, current, fn surface, acc ->
      applied_surface = Map.get(applied, surface)
      basis_surface = Map.get(basis, surface)

      if is_map(applied_surface) and applied_surface != basis_surface do
        Map.put(acc, surface, applied_surface)
      else
        acc
      end
    end)
  end

  @spec merge_pending_items(term(), term(), term()) :: term()

  defp merge_pending_items(current_items, applied_items, basis_items)
       when is_list(current_items) and is_list(applied_items) and is_list(basis_items) do
    new_items = Enum.drop(applied_items, length(basis_items))
    current_items ++ new_items
  end

  @spec merge_app_message_queues(term(), term(), term()) :: term()

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

  @spec queue_for(map(), term()) :: term()

  defp queue_for(queues, surface) when is_map(queues) do
    Map.get(queues, surface) || Map.get(queues, Atom.to_string(surface)) || []
  end

  @spec renumber_rows([map()], integer()) :: {[map()], integer()}

  defp renumber_rows(rows, start_seq) when is_list(rows) and is_integer(start_seq) do
    Enum.map_reduce(rows, start_seq, fn row, prev ->
      next = prev + 1
      {put_row_seq(row, next), next}
    end)
  end

  @spec put_row_seq(map(), integer()) :: map()

  defp put_row_seq(%{} = row, seq) when is_integer(seq) do
    cond do
      Map.has_key?(row, :seq) -> Map.put(row, :seq, seq)
      Map.has_key?(row, "seq") -> Map.put(row, "seq", seq)
      true -> Map.put(row, :seq, seq)
    end
  end

  @spec dbg_seq(map()) :: integer()

  defp dbg_seq(state) when is_map(state) do
    case Map.get(state, :debugger_seq) || Map.get(state, "debugger_seq", 0) do
      seq when is_integer(seq) -> seq
      _ -> 0
    end
  end

  @spec row_dbg_seq(map() | term()) :: integer()

  defp row_dbg_seq(%{seq: seq}) when is_integer(seq), do: seq

  defp row_dbg_seq(row) when is_map(row) do
    case Map.get(row, "seq", 0) do
      seq when is_integer(seq) -> seq
      _ -> 0
    end
  end

  defp row_dbg_seq(_), do: 0

  @spec session_seq(map() | term()) :: integer()

  defp session_seq(%{seq: seq}) when is_integer(seq), do: seq

  defp session_seq(state) when is_map(state) do
    case Map.get(state, :seq, 0) do
      seq when is_integer(seq) -> seq
      _ -> 0
    end
  end

  defp session_seq(_), do: 0
end
