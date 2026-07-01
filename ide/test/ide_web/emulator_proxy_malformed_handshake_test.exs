defmodule IdeWeb.EmulatorProxyMalformedHandshakeTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias IdeWeb.EmulatorProxyClient

  @connect_timeout_ms 3_000

  test "EmulatorProxyClient returns error on malformed phone websocket handshake" do
    {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(listen_socket)
    owner = self()

    accept_task =
      Task.async(fn ->
        {:ok, client} = :gen_tcp.accept(listen_socket, @connect_timeout_ms)
        {:ok, _request} = :gen_tcp.recv(client, 0, @connect_timeout_ms)

        :ok =
          :gen_tcp.send(
            client,
            "kernel_applib_get_log_state timeout error\r\n" <>
              "kernel_applib_get_log_state timeout error\r\n\r\n"
          )

        :gen_tcp.close(client)
      end)

    assert {:error, %WebSockex.RequestError{code: 0, message: message}} =
             EmulatorProxyClient.start_link("ws://127.0.0.1:#{port}/", owner)

    assert message =~ "kernel_applib_get_log_state timeout error"

    refute_receive {:emulator_proxy_upstream_connected, _}, 200

    :ok = Task.await(accept_task, @connect_timeout_ms)
    :gen_tcp.close(listen_socket)
  end
end
