defmodule Ide.Debugger.ReplaySnapshotTypesTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger

  test "replay_recent with frozen replay_rows appends typed replay event payload" do
    slug = "replay_types_#{System.unique_integer([:positive])}"
    on_exit(fn -> Debugger.forget_project(slug) end)

    assert {:ok, _} = Debugger.start_session(slug)
    assert {:ok, _} = Debugger.step(slug, %{"target" => "watch", "message" => "Tick", "count" => 2})

    assert {:ok, _} =
             Debugger.replay_recent(slug, %{
               "replay_rows" => [
                 %{"seq" => 1, "target" => "watch", "message" => "Tick"}
               ]
             })

    assert {:ok, st} = Debugger.snapshot(slug, event_limit: 30)
    replay_event = Enum.find(st.events, &(&1.type == "debugger.replay"))

    assert replay_event.payload.replay_source == "frozen_preview"
    assert replay_event.payload.requested_count == 1
    assert replay_event.payload.replayed_count == 1
  end

  test "continue_from_snapshot appends snapshot_continue payload at cursor" do
    slug = "snapshot_continue_#{System.unique_integer([:positive])}"
    on_exit(fn -> Debugger.forget_project(slug) end)

    assert {:ok, _} = Debugger.start_session(slug)
    assert {:ok, _} = Debugger.step(slug, %{"target" => "watch", "message" => "Tick"})

    assert {:ok, st0} = Debugger.snapshot(slug, event_limit: 5)
    cursor = hd(st0.events).seq

    assert {:ok, _} = Debugger.continue_from_snapshot(slug, %{"cursor_seq" => cursor})

    assert {:ok, st} = Debugger.snapshot(slug, event_limit: 10)
    cont = Enum.find(st.events, &(&1.type == "debugger.snapshot_continue"))

    assert cont.payload.cursor_seq == cursor
    assert cont.payload.source == "cursor_snapshot"
  end
end
