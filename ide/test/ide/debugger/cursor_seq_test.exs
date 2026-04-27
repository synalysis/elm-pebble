defmodule Ide.Debugger.CursorSeqTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.CursorSeq

  test "resolve_at_or_before picks exact or nearest lower seq" do
    events = [%{seq: 9}, %{seq: 6}, %{seq: 3}]

    assert CursorSeq.resolve_at_or_before(events, 6) == 6
    assert CursorSeq.resolve_at_or_before(events, 7) == 6
    assert CursorSeq.resolve_at_or_before(events, 2) == 9
    assert CursorSeq.resolve_at_or_before(events, nil) == 9
  end

  test "resolve_at_or_before returns nil for empty events" do
    assert CursorSeq.resolve_at_or_before([], 5) == nil
  end

  test "resolve_before picks baseline before current and honors requested bound" do
    events = [%{seq: 9}, %{seq: 6}, %{seq: 3}, %{seq: 1}]

    assert CursorSeq.resolve_before(events, 9, nil) == 6
    assert CursorSeq.resolve_before(events, 9, 3) == 3
    assert CursorSeq.resolve_before(events, 9, 0) == 1
    assert CursorSeq.resolve_before(events, 1, nil) == nil
  end
end
