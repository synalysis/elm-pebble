defmodule IdeWeb.EmulatorPhoneInstallProxyLiveTest do
  @moduledoc false

  use ExUnit.Case, async: false

  @moduletag :live_emulator

  alias Ide.Emulator
  alias Ide.Emulator.Session
  alias Ide.TestSupport.{EmulatorLaunch, EmulatorSessionEnv}
  alias IdeWeb.EmulatorProxyClient

  @connect_timeout_ms 10_000

  @tag :slow
  test "EmulatorProxyClient reconnects after upstream websocket closes during live session" do
    EmulatorSessionEnv.run_live(fn ->
      assert {:ok, info} =
               EmulatorLaunch.launch(
                 project_slug: "phone-install-proxy-live",
                 platform: "basalt",
                 artifact_path: nil,
                 has_phone_companion: true,
                 has_companion_preferences: false
               )

      try do
        {:ok, pid} = Emulator.lookup(info.id)
        port = Session.local_port(pid, :phone)
        owner = self()

        assert {:ok, first} =
                 EmulatorProxyClient.start_link("ws://127.0.0.1:#{port}/", owner)

        assert_receive :emulator_proxy_upstream_connected, @connect_timeout_ms
        Process.exit(first, :normal)
        assert_receive {:emulator_proxy_closed, _}, @connect_timeout_ms

        assert {:ok, second} =
                 EmulatorProxyClient.start_link("ws://127.0.0.1:#{port}/", owner)

        assert_receive :emulator_proxy_upstream_connected, @connect_timeout_ms
        Process.exit(second, :normal)
      after
        assert :ok = Emulator.kill(info.id)
      end
    end)
  end
end
