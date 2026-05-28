defmodule Ide.Debugger.TraceExchange.Wire do
  @moduledoc false

  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types

  @type runtime_event :: Types.runtime_event()

  @spec normalize_term(Types.wire_input() | atom()) :: Types.normalized_export_term()
  def normalize_term(%Surface{} = surface), do: normalize_term(Surface.to_map(surface))

  def normalize_term(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), normalize_term(v)} end)
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Map.new()
  end

  def normalize_term(list) when is_list(list), do: Enum.map(list, &normalize_term/1)

  def normalize_term(other), do: other

  @spec normalize_event(runtime_event()) :: Types.trace_export_event_row()
  def normalize_event(event) when is_map(event) do
    %{
      "companion" => normalize_term(Map.get(event, :companion, %{})),
      "payload" => normalize_term(Map.get(event, :payload, %{})),
      "phone" => normalize_term(Map.get(event, :phone, %{})),
      "seq" => Map.get(event, :seq),
      "type" => Map.get(event, :type),
      "watch" => normalize_term(Map.get(event, :watch, %{}))
    }
  end

  @spec normalize_events_with_snapshot_refs([runtime_event()]) :: [Types.trace_export_event_row()]
  def normalize_events_with_snapshot_refs(events) when is_list(events) do
    {rows, _previous} =
      Enum.map_reduce(events, %{}, fn event, previous ->
        row = normalize_event(event)
        seq = Map.get(row, "seq")

        refs =
          ["watch", "companion", "phone"]
          |> Enum.reduce(%{}, fn surface, acc ->
            current_snapshot = Map.get(row, surface)

            case Map.get(previous, surface) do
              %{seq: prev_seq, snapshot: snapshot}
              when snapshot == current_snapshot and is_integer(prev_seq) ->
                Map.put(acc, surface, prev_seq)

              _ ->
                acc
            end
          end)

        changed_surfaces =
          ["watch", "companion", "phone"]
          |> Enum.reject(&Map.has_key?(refs, &1))

        row =
          row
          |> maybe_put_snapshot_refs(refs)
          |> Map.put("snapshot_changed_surfaces", changed_surfaces)

        next_previous =
          ["watch", "companion", "phone"]
          |> Enum.reduce(previous, fn surface, acc ->
            snapshot = Map.get(row, surface)

            if is_map(snapshot) do
              Map.put(acc, surface, %{seq: seq, snapshot: snapshot})
            else
              acc
            end
          end)

        {row, next_previous}
      end)

    rows
  end

  @spec maybe_put_snapshot_refs(Types.trace_export_event_row(), Types.trace_export_snapshot_refs()) ::
          Types.trace_export_event_row()
  defp maybe_put_snapshot_refs(row, refs) when map_size(refs) == 0, do: row
  defp maybe_put_snapshot_refs(row, refs), do: Map.put(row, "snapshot_refs", refs)
end
