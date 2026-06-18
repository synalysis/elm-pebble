defmodule Ide.Emulator.WorkflowTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.Workflow

  test "launch_error_message explains protocol router port conflicts" do
    message = Workflow.launch_error_message({:protocol_router_start_failed, :eaddrinuse})

    assert message =~ "port is already in use"
    assert message =~ "restart the IDE server"
    refute message =~ "eaddrinuse"
  end

  test "launch_error_message explains other protocol router failures" do
    message = Workflow.launch_error_message({:protocol_router_start_failed, :einval})

    assert message =~ "communication bridge"
    assert message =~ "restart the IDE server"
  end
end
