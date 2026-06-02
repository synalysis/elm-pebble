defmodule Elmx.CoreTaskTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Core.Task

  test "map, map2, andThen on resolved tasks" do
    assert {:Ok, 22} = Task.map(&(&1 * 2), {:Ok, 11})
    assert {:Err, :nope} = Task.map(&(&1 * 2), {:Err, :nope})
    assert {:Ok, 7} = Task.map2(&+/2, {:Ok, 3}, {:Ok, 4})
    assert {:Err, :bad} = Task.map2(&+/2, {:Err, :bad}, {:Ok, 4})
    assert {:Ok, 12} = Task.and_then(fn n -> {:Ok, n + 10} end, {:Ok, 2})
    assert {:Err, :x} = Task.and_then(fn _ -> {:Ok, 1} end, {:Err, :x})
  end

  test "perform delivers immediate cmd for Ok tasks" do
    cmd = Task.perform(fn n -> %{ctor: :Tick, args: [n]} end, {:Ok, 1})
    assert cmd["kind"] == "cmd.task.immediate"
    assert is_binary(cmd["message"])
  end
end
