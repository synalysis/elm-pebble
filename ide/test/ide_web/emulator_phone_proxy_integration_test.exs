defmodule IdeWeb.EmulatorPhoneProxyIntegrationTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Ide.Emulator
  alias Ide.Emulator.Session
  alias Ide.Emulator.Session.ProcessHost
  alias Ide.TestSupport.EmulatorSessionEnv
  alias Ide.TestSupport.EmulatorLaunch
  alias Ide.Emulator.VncHandshake
  alias Ide.TestSupport.EmulatorProxyHandshake
  alias IdeWeb.{EmulatorProxyClient, EmulatorProxySocket}

  @connect_timeout_ms 5_000

  test "pypkjs phone port accepts websocket within #{@connect_timeout_ms}ms" do
    EmulatorSessionEnv.run_live(fn ->
      assert {:ok, info} =
               EmulatorLaunch.launch(
                 project_slug: "phone-proxy-test",
                 platform: "basalt",
                 artifact_path: nil,
                 has_phone_companion: false,
                 has_companion_preferences: false
               )

      try do
        {:ok, pid} = Emulator.lookup(info.id)
        port = Session.local_port(pid, :phone)
        assert ProcessHost.tcp_port_open?(port)
        assert ws_connects?(port, @connect_timeout_ms)
      after
        assert :ok = Emulator.kill(info.id)
      end
    end)
  end

  test "EmulatorProxySocket relays RFB banner from live vnc port" do
    EmulatorSessionEnv.run_live(fn ->
      assert {:ok, info} =
               EmulatorLaunch.launch(
                 project_slug: "vnc-proxy-socket-test",
                 platform: "diorite",
                 artifact_path: nil,
                 has_phone_companion: false,
                 has_companion_preferences: false
               )

      try do
        {:ok, pid} = Emulator.lookup(info.id)
        port = Session.local_port(pid, :vnc)

        assert {:ok, state} = EmulatorProxySocket.init(%{target: {:tcp, "127.0.0.1", port}})
        assert_receive {:tcp, socket, banner}, @connect_timeout_ms
        assert is_port(socket)
        assert Ide.Emulator.VncReady.version_line_complete?(banner)

        assert {:push, {:binary, ^banner}, _} =
                 EmulatorProxySocket.handle_info({:tcp, socket, banner}, state)
      after
        assert :ok = Emulator.kill(info.id)
      end
    end)
  end

  test "VNC completes handshake on tcp port" do
    EmulatorSessionEnv.run_live(fn ->
      assert {:ok, info} =
               EmulatorLaunch.launch(
                 project_slug: "vnc-handshake-test",
                 platform: "diorite",
                 artifact_path: nil,
                 has_phone_companion: false,
                 has_companion_preferences: false
               )

      try do
        {:ok, pid} = Emulator.lookup(info.id)
        port = Session.local_port(pid, :vnc)
        assert {:ok, {width, height}} = VncHandshake.server_init(port, @connect_timeout_ms)
        assert width > 0 and height > 0
      after
        assert :ok = Emulator.kill(info.id)
      end
    end)
  end

  test "EmulatorProxySocket completes VNC handshake" do
    EmulatorSessionEnv.run_live(fn ->
      assert {:ok, info} =
               EmulatorLaunch.launch(
                 project_slug: "vnc-proxy-handshake-test",
                 platform: "diorite",
                 artifact_path: nil,
                 has_phone_companion: false,
                 has_companion_preferences: false
               )

      try do
        {:ok, pid} = Emulator.lookup(info.id)
        port = Session.local_port(pid, :vnc)

        assert {:ok, {width, height}} =
                 EmulatorProxyHandshake.through_proxy(port, @connect_timeout_ms)

        assert width > 0 and height > 0
      after
        assert :ok = Emulator.kill(info.id)
      end
    end)
  end

  test "vnc port serves RFB banner within #{@connect_timeout_ms}ms" do
    EmulatorSessionEnv.run_live(fn ->
      assert {:ok, info} =
               EmulatorLaunch.launch(
                 project_slug: "vnc-proxy-test",
                 platform: "diorite",
                 artifact_path: nil,
                 has_phone_companion: false,
                 has_companion_preferences: false
               )

      try do
        {:ok, pid} = Emulator.lookup(info.id)
        assert info.display_ready == true
        port = Session.local_port(pid, :vnc)
        assert ProcessHost.tcp_port_open?(port)

        assert {:ok, socket} =
                 :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], 5_000)

        try do
          assert {:ok, "RFB "} = :gen_tcp.recv(socket, 4, @connect_timeout_ms)
        after
          :gen_tcp.close(socket)
        end
      after
        assert :ok = Emulator.kill(info.id)
      end
    end)
  end

  test "EmulatorProxyClient reaches pypkjs within #{@connect_timeout_ms}ms" do
    EmulatorSessionEnv.run_live(fn ->
      assert {:ok, info} =
               EmulatorLaunch.launch(
                 project_slug: "phone-proxy-test",
                 platform: "basalt",
                 artifact_path: nil,
                 has_phone_companion: false,
                 has_companion_preferences: false
               )

      try do
        {:ok, pid} = Emulator.lookup(info.id)
        port = Session.local_port(pid, :phone)
        owner = self()

        assert {:ok, _client} =
                 EmulatorProxyClient.start_link("ws://127.0.0.1:#{port}/", owner)

        assert_receive :emulator_proxy_upstream_connected, @connect_timeout_ms
      after
        assert :ok = Emulator.kill(info.id)
      end
    end)
  end

  defp ws_connects?(port, timeout_ms) do
    owner = self()

    case WebSockex.start_link(
           "ws://127.0.0.1:#{port}/",
           EmulatorPhoneProxyIntegrationTest.ProbeClient,
           %{owner: owner},
           async_connect: true
         ) do
      {:ok, client} ->
        result =
          receive do
            :pypkjs_ws_connected -> true
          after
            timeout_ms -> false
          end

        Process.exit(client, :normal)
        result

      {:error, _reason} ->
        false
    end
  end
end

defmodule EmulatorPhoneProxyIntegrationTest.ProbeClient do
  @moduledoc false
  use WebSockex

  def handle_connect(_conn, %{owner: owner}) do
    send(owner, :pypkjs_ws_connected)
    {:ok, %{}}
  end

  def handle_frame(_frame, state), do: {:ok, state}
end
