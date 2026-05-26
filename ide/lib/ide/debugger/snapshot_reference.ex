defmodule Ide.Debugger.SnapshotReference do
  @moduledoc false

  alias Ide.Debugger.TraceExchange
  alias Ide.Debugger.Types

  @spec rows([Types.runtime_event()]) :: [map()]
  def rows(events) when is_list(events) do
    events
    |> Enum.sort_by(& &1.seq)
    |> TraceExchange.normalize_events_with_snapshot_refs()
    |> Enum.map(fn row ->
      %{
        "seq" => Map.get(row, "seq"),
        "snapshot_refs" => Map.get(row, "snapshot_refs", %{}),
        "snapshot_changed_surfaces" =>
          Map.get(row, "snapshot_changed_surfaces", ["watch", "companion", "phone"])
      }
    end)
  end

  def rows(_events), do: []
end
