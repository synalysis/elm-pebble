defmodule Ide.Debugger.AutoTickWorkersTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.AutoTickWorkers
  alias Ide.Debugger.SessionDefaults

  test "stop_worker clears worker pid and resets auto_tick" do
    worker = spawn(fn -> receive do :stop -> :ok end end)

    state = %{
      auto_tick: Map.put(SessionDefaults.default_auto_tick(), :worker_pid, worker)
    }

    assert AutoTickWorkers.stop_worker(state).auto_tick.worker_pid == nil
    send(worker, :stop)
  end
end
