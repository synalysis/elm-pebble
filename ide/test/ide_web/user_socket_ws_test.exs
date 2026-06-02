defmodule IdeWeb.UserSocketWsTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Ide.Emulator
  alias Ide.Emulator.VncReady
  alias Ide.TestSupport.{EmulatorLaunch, EmulatorSessionEnv}

  @http_port 40_203
  @handshake_timeout_ms 30_000

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

  test "socket websocket accepts emulator_vnc join and relays RFB banner" do
    EmulatorSessionEnv.run_live(fn ->
      assert {:ok, info} = launch_diorite("user-socket-vnc-test")

      try do
        assert info.display_ready == true
        owner = self()

        assert {:ok, client} =
                 WebSockex.start_link(
                   user_socket_ws_url(),
                   __MODULE__.VncJoinClient,
                   %{owner: owner, session_id: info.id, acc: <<>>},
                   async_connect: true
                 )

        assert_receive :user_socket_vnc_banner, @handshake_timeout_ms
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

  defp user_socket_ws_url do
    "ws://127.0.0.1:#{@http_port}/socket/websocket?" <>
      URI.encode_query(%{"vsn" => "2.0.0"})
  end

  defmodule VncJoinClient do
    @moduledoc false
    use WebSockex

    alias Ide.Emulator.VncReady

    @impl WebSockex
    def handle_connect(_conn, state) do
      send(self(), :join_channel)
      {:ok, state}
    end

    @impl WebSockex
    def handle_info(:join_channel, %{session_id: session_id} = state) do
      ref = "1"
      msg = Jason.encode!([ref, ref, "emulator_vnc:#{session_id}", "phx_join", %{}])
      {:reply, {:text, msg}, state}
    end

    @impl WebSockex
    def handle_frame({:text, payload}, state) do
      case Jason.decode(payload) do
        {:ok, [_join_ref, _ref, topic, "phx_reply", %{"status" => "ok", "response" => response}]} ->
          if topic == "emulator_vnc:#{state.session_id}" do
            case response do
              %{"initial" => encoded} when is_binary(encoded) ->
                acc = state.acc <> Base.decode64!(encoded)

                if VncReady.version_line_complete?(acc) do
                  send(state.owner, :user_socket_vnc_banner)
                end

                {:ok, %{state | acc: acc}}

              _ ->
                {:ok, state}
            end
          else
            {:ok, state}
          end

        {:ok, other} ->
          flunk("unexpected phoenix text frame: #{inspect(other)}")
          {:ok, state}

        {:error, reason} ->
          flunk("invalid phoenix text frame: #{inspect(reason)} payload=#{inspect(payload)}")
          {:ok, state}
      end
    end

    @impl WebSockex
    def handle_frame({:binary, raw}, %{owner: owner, acc: acc} = state) do
      case decode_push_binary(raw) do
        {:ok, "frame", data} ->
          acc = acc <> data

          if VncReady.version_line_complete?(acc) do
            send(owner, :user_socket_vnc_banner)
          end

          {:ok, %{state | acc: acc}}

        other ->
          flunk("unexpected phoenix binary frame: #{inspect(other)}")
          {:ok, state}
      end
    end

    defp decode_push_binary(<<
           0,
           join_ref_size,
           topic_size,
           event_size,
           _join_ref::binary-size(join_ref_size),
           _topic::binary-size(topic_size),
           event::binary-size(event_size),
           data::binary
         >>) do
      {:ok, event, data}
    end

    defp decode_push_binary(_), do: :error
  end
end
