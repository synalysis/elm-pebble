defmodule IdeWeb.EmulatorVncHttpWsTest do
  @moduledoc false

  use IdeWeb.ConnCase, async: false

  alias Ide.Emulator
  alias Ide.Emulator.VncReady
  alias Ide.TestSupport.{EmulatorLaunch, EmulatorSessionEnv}

  @handshake_timeout_ms 30_000
  @http_port 40_202

  setup_all do
    {:ok, bandit} =
      Bandit.start_link(
        plug: {IdeWeb.Endpoint, []},
        port: @http_port,
        ip: :loopback
      )

    on_exit(fn -> Process.exit(bandit, :shutdown) end)
    :ok
  end

  test "vnc websocket upgrade delivers RFB banner", %{conn: _conn} do
    EmulatorSessionEnv.run_live(fn ->
      assert {:ok, info} = launch_diorite("vnc-http-banner-test")

      try do
        assert info.display_ready == true
        assert vnc_port_open?(info.id)
        owner = self()

        assert {:ok, client} =
                 WebSockex.start_link(
                   vnc_ws_url(info.id),
                   __MODULE__.BannerClient,
                   %{owner: owner, acc: <<>>},
                   async_connect: true
                 )

        assert_receive :vnc_ws_banner, @handshake_timeout_ms
        Process.exit(client, :normal)
      after
        assert :ok = Emulator.kill(info.id)
      end
    end)
  end

  test "vnc websocket upgrade completes RFB handshake", %{conn: _conn} do
    EmulatorSessionEnv.run_live(fn ->
      assert {:ok, info} = launch_diorite("vnc-http-handshake-test")

      try do
        assert info.display_ready == true
        assert vnc_port_open?(info.id)
        owner = self()

        assert {:ok, client} =
                 WebSockex.start_link(
                   vnc_ws_url(info.id),
                   __MODULE__.HandshakeClient,
                 %{owner: owner, acc: <<>>, phase: :await_banner},
                 async_connect: true
               )

        assert_receive {:vnc_ws_handshake_ok, width, height}, @handshake_timeout_ms
        assert width > 0 and height > 0
        Process.exit(client, :normal)
      after
        assert :ok = Emulator.kill(info.id)
      end
    end)
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

  defp vnc_ws_url(id), do: "ws://127.0.0.1:#{@http_port}/api/emulator/#{id}/ws/vnc"

  defp vnc_port_open?(id) do
    with {:ok, pid} <- Emulator.lookup(id),
         port when is_integer(port) <- Ide.Emulator.Session.local_port(pid, :vnc) do
      Ide.Emulator.Session.tcp_port_open?(port)
    else
      _ -> false
    end
  end

  defmodule BannerClient do
    @moduledoc false
    use WebSockex

    alias Ide.Emulator.VncReady

    @impl WebSockex
    def handle_connect(_conn, state), do: {:ok, state}

    @impl WebSockex
    def handle_frame({:binary, data}, %{owner: owner, acc: acc} = state) do
      acc = acc <> data

      if VncReady.version_line_complete?(acc) do
        send(owner, :vnc_ws_banner)
        {:ok, state}
      else
        {:ok, %{state | acc: acc}}
      end
    end
  end

  defmodule HandshakeClient do
    @moduledoc false
    use WebSockex

    alias Ide.Emulator.VncReady

    @client_version "RFB 003.008\n"

    @impl WebSockex
    def handle_connect(_conn, state), do: {:ok, state}

    @impl WebSockex
    def handle_frame({:binary, data}, state) do
      acc = state.acc <> data

      case state.phase do
        :await_banner ->
          if VncReady.version_line_complete?(acc) do
            {:reply, {:binary, @client_version}, %{state | acc: <<>>, phase: :await_security}}
          else
            {:ok, %{state | acc: acc}}
          end

        :await_security ->
          case security_types(acc) do
            {:ok, types} ->
              if 1 in types do
                {:reply, {:binary, <<1>>}, %{state | acc: <<>>, phase: :await_security_result}}
              else
                {:close, {1002, "no VNC security type 1"}, state}
              end

            :more ->
              {:ok, %{state | acc: acc}}
          end

        :await_security_result ->
          if byte_size(acc) >= 4 do
            <<0, 0, 0, 0, rest::binary>> = acc
            {:reply, {:binary, <<1>>}, %{state | acc: rest, phase: :await_server_init}}
          else
            {:ok, %{state | acc: acc}}
          end

        :await_server_init ->
          if byte_size(acc) >= 24 do
            <<width::unsigned-big-16, height::unsigned-big-16, _pf::binary-size(16),
              _name_len::unsigned-big-32>> = binary_part(acc, 0, 24)

            send(state.owner, {:vnc_ws_handshake_ok, width, height})
            {:ok, state}
          else
            {:ok, %{state | acc: acc}}
          end
      end
    end

    defp security_types(acc) do
      if byte_size(acc) >= 1 do
        <<count::unsigned-8, rest::binary>> = acc

        if byte_size(rest) >= count do
          {:ok, :binary.bin_to_list(binary_part(rest, 0, count))}
        else
          :more
        end
      else
        :more
      end
    end
  end

end
