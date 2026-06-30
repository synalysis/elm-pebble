defmodule Elmx.CoreTaskTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Core.Task

  test "map, map2, map3, andThen, sequence, onError, mapError, and attempt on resolved tasks" do
    assert {:Ok, 22} = Task.map(&(&1 * 2), {:Ok, 11})
    assert {:Err, :nope} = Task.map(&(&1 * 2), {:Err, :nope})
    assert {:Ok, 7} = Task.map2(&+/2, {:Ok, 3}, {:Ok, 4})
    assert {:Err, :bad} = Task.map2(&+/2, {:Err, :bad}, {:Ok, 4})
    assert {:Ok, 6} = Task.map3(fn a, b, c -> a + b + c end, {:Ok, 1}, {:Ok, 2}, {:Ok, 3})
    assert {:Ok, 12} = Task.and_then(fn n -> {:Ok, n + 10} end, {:Ok, 2})
    assert {:Err, :x} = Task.and_then(fn _ -> {:Ok, 1} end, {:Err, :x})
    assert {:Ok, [1, 2, 3]} = Task.sequence([{:Ok, 1}, {:Ok, 2}, {:Ok, 3}])
    assert {:Ok, 42} = Task.on_error(fn _ -> {:Ok, 42} end, {:Err, :missing})
    assert {:Ok, 9} = Task.map_error(&inspect/1, {:Ok, 9})
    assert {:Err, ":nope"} = Task.map_error(&inspect/1, {:Err, :nope})
  end

  test "attempt delivers immediate cmd for Ok and Err tasks" do
    ok_cmd = Task.attempt(fn result -> %{ctor: :Got, args: [result]} end, {:Ok, 1})
    assert ok_cmd["kind"] == "cmd.task.immediate"

    err_cmd = Task.attempt(fn result -> %{ctor: :Got, args: [result]} end, {:Err, :bad})
    assert err_cmd["kind"] == "cmd.task.immediate"
  end

  test "perform delivers immediate cmd for Ok tasks" do
    cmd = Task.perform(fn n -> %{ctor: :Tick, args: [n]} end, {:Ok, 1})
    assert cmd["kind"] == "cmd.task.immediate"
    assert is_binary(cmd["message"])
  end

  test "perform force-resolves succeed tasks from Time.now-style helpers" do
    cmd = Task.perform(fn ms -> {:Tick, ms} end, Task.succeed(1_234_567_890))
    assert cmd["kind"] == "cmd.task.immediate"
    assert cmd["message"] == "Tick"
    assert get_in(cmd, ["message_value", "args"]) == [1_234_567_890]
  end
end
