defmodule Elmx.FollowupsTest do
  use ExUnit.Case

  alias Elmx.Runtime.{Cmd, Followups}

  test "timer_after produces timer_command followup row" do
    cmd = Cmd.timer_after(1000, :Tick)

    assert [%{"source" => "timer_command", "message" => "Tick"}] =
             Followups.from_commands(cmd)
  end

  test "companion bridge storage get produces companion_bridge_command followup" do
    cmd = Cmd.companion_bridge("storage", "get", key: "theme", callback: "GotStorage")

    assert [%{"source" => "companion_bridge_command", "message" => "GotStorage"}] =
             Followups.from_commands(cmd, source_root: "phone")
  end

  test "protocol_watch_to_phone produces protocol followup row" do
    cmd = Cmd.protocol_watch_to_phone(:RequestWeather)

    assert [%{"source" => "protocol_command", "message" => "RequestWeather"}] =
             Followups.from_commands(cmd)
  end

  test "init on simple_project returns device and protocol followups" do
    revision = "followups-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, %{entry_module: module}} =
             Elmx.compile_in_memory(
               Path.expand("fixtures/simple_project", __DIR__),
               %{
                 entry_module: "Main",
                 revision: revision,
                 strip_dead_code: true,
                 mode: :ide_runtime
               }
             )

    assert {:ok, payload} =
             Elmx.Runtime.Executor.execute_generated(module, %{
               "current_model" => %{"launch_context" => %{}},
               "message" => nil
             })

    followups = payload[:followup_messages] || payload["followup_messages"] || []
    sources = Enum.map(followups, &(&1["source"] || &1[:source]))

    assert "protocol_command" in sources
    assert "device_command" in sources
  end
end
