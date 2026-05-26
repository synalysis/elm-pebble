defmodule Ide.Debugger.EventLogTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.EventLog
  alias Ide.Debugger.Types.TickEventPayload

  defp base_state do
    %{
      seq: 0,
      events: [],
      debugger_seq: 0,
      debugger_timeline: [],
      watch: %{},
      companion: %{},
      phone: %{}
    }
  end

  test "append increments seq and caps history" do
    payload = TickEventPayload.from_tick("all", 1, ["watch"])

    state =
      Enum.reduce(1..3, base_state(), fn _, st ->
        EventLog.append(st, "debugger.tick", payload, limit: 2)
      end)

    assert state.seq == 3
    assert length(state.events) == 2
    assert hd(state.events).type == "debugger.tick"
  end

  test "append_debugger_event records timeline row" do
    state =
      EventLog.append_debugger_event(base_state(), "runtime", :watch, "Tick", "tick",
        source_root_for_target: fn :watch -> "watch" end
      )

    assert state.debugger_seq == 1
    assert [%{target: "watch", message: "Tick"}] = state.debugger_timeline
  end
end
