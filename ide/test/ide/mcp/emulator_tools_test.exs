defmodule Ide.Mcp.EmulatorToolsTest do
  use ExUnit.Case, async: false

  alias Ide.Emulator
  alias Ide.Mcp.Tools
  alias Ide.TestSupport.{EmulatorLaunch, EmulatorSessionEnv}

  test "embedded emulator tools are build-scoped" do
    tool_names = Tools.tool_definitions([:build]) |> Enum.map(& &1.name)
    assert "emulator_launch" in tool_names
    assert "emulator_install" in tool_names
    assert "emulator_ping" in tool_names
    assert "emulator_kill" in tool_names
    assert "emulator_run" in tool_names
    assert "emulator_logs" in tool_names

    assert {:error, denied} =
             Tools.call("emulator.launch", %{"slug" => "any", "platform" => "basalt"}, [:read])

    assert String.contains?(denied, "not permitted")
  end

  test "emulator.ping and emulator.kill work for dry-run sessions" do
    EmulatorSessionEnv.run(fn ->
      assert {:ok, info} =
               EmulatorLaunch.launch(project_slug: "mcp-emulator", platform: "basalt", artifact_path: nil)

      assert {:ok, pinged} =
               Tools.call("emulator.ping", %{"session_id" => info.id}, [:build])

      assert pinged.session_id == info.id
      assert pinged.alive == true
      assert pinged.session.id == info.id

      assert {:ok, killed} =
               Tools.call("emulator.kill", %{"session_id" => info.id}, [:build])

      assert killed.status == "ok"
    end)
  end

  test "emulator.install reports missing protocol router in dry-run sessions" do
    EmulatorSessionEnv.run(fn ->
      assert {:ok, info} =
               EmulatorLaunch.launch(
                 project_slug: "mcp-emulator-install",
                 platform: "basalt",
                 artifact_path: "/tmp/app.pbw"
               )

      assert {:error, message} =
               Tools.call(
                 "emulator.install",
                 %{"session_id" => info.id, "wait_display_ready" => false},
                 [:build]
               )

      assert message =~ "protocol router is not running"
      assert :ok = Emulator.kill(info.id)
    end)
  end
end
