defmodule IdeWeb.EmulatorVncChannelHandshakeTest do
  @moduledoc false

  use ExUnit.Case, async: false
  import Phoenix.ChannelTest

  alias Ide.Emulator
  alias Ide.Emulator.Session
  alias Ide.TestSupport.{EmulatorLaunch, EmulatorProxyHandshake, EmulatorSessionEnv}

  @endpoint IdeWeb.Endpoint
  @client_version "RFB 003.008\n"
  @handshake_timeout_ms 10_000

  test "fresh tcp handshake works on session vnc port" do
    EmulatorSessionEnv.run_live(fn ->
      assert {:ok, info} = launch_diorite("vnc-tcp-handshake-test")

      try do
        assert info.display_ready == true
        {:ok, pid} = Emulator.lookup(info.id)
        port = Session.local_port(pid, :vnc)
        assert {:ok, {width, height}} = EmulatorProxyHandshake.through_proxy(port, @handshake_timeout_ms)
        assert width > 0 and height > 0
      after
        assert :ok = Emulator.kill(info.id)
      end
    end)
  end

  test "claimed session tcp accepts client version and responds" do
    EmulatorSessionEnv.run_live(fn ->
      assert {:ok, info} = launch_diorite("vnc-claimed-tcp-test")

      try do
        assert info.display_ready == true
        {:ok, pid} = Emulator.lookup(info.id)
        assert {:ok, _banner, tcp, _extra} = claim_vnc_for_test(pid)
        assert :gen_tcp.send(tcp, @client_version) == :ok

        assert {:ok, security} = :gen_tcp.recv(tcp, 0, @handshake_timeout_ms)
        assert byte_size(security) >= 2

        Session.return_vnc_tcp(pid, tcp)
      after
        assert :ok = Emulator.kill(info.id)
      end
    end)
  end

  test "spawned process can handshake on claimed session tcp" do
    EmulatorSessionEnv.run_live(fn ->
      assert {:ok, info} = launch_diorite("vnc-spawn-tcp-test")

      try do
        assert info.display_ready == true
        {:ok, pid} = Emulator.lookup(info.id)

        parent = self()

        spawn(fn ->
          assert {:ok, _banner, tcp, _extra} = claim_vnc_for_test(pid)
          assert :gen_tcp.send(tcp, @client_version) == :ok
          result = :gen_tcp.recv(tcp, 0, @handshake_timeout_ms)
          send(parent, {:spawn_recv, result})
        end)

        assert_receive {:spawn_recv, {:ok, security}}, @handshake_timeout_ms
        assert byte_size(security) >= 2
      after
        assert :ok = Emulator.kill(info.id)
      end
    end)
  end

  test "channel relays client frames after join initial" do
    EmulatorSessionEnv.run_live(fn ->
      assert {:ok, info} = launch_diorite("vnc-channel-handshake-test")

      try do
        assert info.display_ready == true

        assert {:ok, socket} = connect(IdeWeb.UserSocket, %{}, endpoint: @endpoint)
        assert {:ok, reply, socket} = subscribe_and_join(socket, "emulator_vnc:#{info.id}", %{})

        encoded = Map.get(reply, "initial") || Map.get(reply, :initial)
        assert is_binary(encoded), "expected initial banner in join reply, got: #{inspect(reply)}"

        ref = push(socket, "frame", %{b64: Base.encode64(@client_version)})
        assert_reply ref, :ok, _, 5_000

        assert_push "frame", payload, @handshake_timeout_ms

        security =
          case payload do
            %{b64: encoded} when is_binary(encoded) -> Base.decode64!(encoded)
            %{"b64" => encoded} when is_binary(encoded) -> Base.decode64!(encoded)
            {:binary, data} when is_binary(data) -> data
            data when is_binary(data) -> data
            other -> flunk("unexpected frame payload: #{inspect(other)}")
          end

        assert byte_size(security) >= 2
        <<count::unsigned-8, _types::binary>> = security
        assert count >= 1
      after
        assert :ok = Emulator.kill(info.id)
      end
    end)
  end

  defp claim_vnc_for_test(pid) do
    with {:ok, banner} <- Session.vnc_rfb_banner(pid),
         {:ok, tcp, extra} <- Session.claim_vnc_tcp(pid) do
      :inet.setopts(tcp, active: false, packet: :raw)
      {:ok, banner, tcp, extra}
    end
  end

  defp launch_diorite(slug) do
    EmulatorLaunch.launch(
      project_slug: slug,
      platform: "diorite",
      artifact_path: nil,
      has_phone_companion: false,
      has_companion_preferences: false
    )
  end
end
