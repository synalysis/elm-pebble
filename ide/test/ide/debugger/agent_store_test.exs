defmodule Ide.Debugger.AgentStoreTest do
  use ExUnit.Case, async: false

  alias Ide.Debugger.AgentStore
  alias Ide.Debugger.SessionDefaults

  @tag :debugger_agent
  test "update stores per-project state" do
    agent = start_supervised_agent!()

    assert {:ok, state} =
             AgentStore.update(
               "proj-a",
               fn _ -> SessionDefaults.default_state("proj-a") |> Map.put(:running, true) end,
               agent: agent
             )

    assert state.running

    assert fetched = AgentStore.fetch("proj-a", agent: agent)
    assert fetched.running
  end

  defp start_supervised_agent! do
    {:ok, pid} = Agent.start_link(fn -> %{} end)
    on_exit(fn -> if Process.alive?(pid), do: Agent.stop(pid, :normal, 5_000) end)
    pid
  end
end
