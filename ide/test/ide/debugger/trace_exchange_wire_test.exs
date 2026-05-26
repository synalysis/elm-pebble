defmodule Ide.Debugger.TraceExchangeWireTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.TraceExchange.Wire

  test "normalize_events_with_snapshot_refs records unchanged surface refs" do
    event = %{
      seq: 1,
      type: "debugger.tick",
      payload: %{},
      watch: %{"model" => %{}},
      companion: %{"model" => %{}},
      phone: %{"model" => %{}}
    }

    duplicate = Map.put(event, :seq, 2)

    [first, second] = Wire.normalize_events_with_snapshot_refs([event, duplicate])

    assert first["seq"] == 1
    assert second["seq"] == 2
    assert get_in(second, ["snapshot_refs", "watch"]) == 1
    refute "watch" in second["snapshot_changed_surfaces"]
  end
end
