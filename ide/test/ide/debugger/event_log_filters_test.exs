defmodule Ide.Debugger.EventLogFiltersTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.EventLogFilters

  defp event(seq, type), do: %{seq: seq, type: type, payload: %{}}

  test "at_or_before_seq filters by cursor" do
    events = [event(1, "a"), event(2, "b"), event(3, "c")]

    assert EventLogFilters.at_or_before_seq(events, nil) == events
    assert EventLogFilters.at_or_before_seq(events, 2) == [event(1, "a"), event(2, "b")]
  end

  test "by_types and since_seq trim event log on state" do
    state = %{
      events: [
        event(1, "debugger.tick"),
        event(2, "debugger.update_in"),
        event(3, "debugger.tick")
      ]
    }

    assert EventLogFilters.by_types(state, ["debugger.tick"]).events ==
             [event(1, "debugger.tick"), event(3, "debugger.tick")]

    assert EventLogFilters.since_seq(state, 1).events ==
             [event(2, "debugger.update_in"), event(3, "debugger.tick")]
  end
end
