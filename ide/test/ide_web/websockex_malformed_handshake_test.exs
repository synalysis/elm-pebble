defmodule IdeWeb.WebsockexMalformedHandshakeTest do
  @moduledoc false

  use ExUnit.Case, async: true

  @connect_timeout_ms 3_000

  test "malformed websocket handshake returns RequestError instead of CaseClauseError" do
    {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(listen_socket)

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

    result =
      WebSockex.start_link(
        "ws://127.0.0.1:#{port}/",
        __MODULE__.ProbeClient,
        %{}
      )

    assert {:error, %WebSockex.RequestError{code: 0, message: message}} = result
    assert message =~ "kernel_applib_get_log_state timeout error"

    :ok = Task.await(accept_task, @connect_timeout_ms)
    :gen_tcp.close(listen_socket)
  end
end

defmodule IdeWeb.WebsockexMalformedHandshakeTest.ProbeClient do
  @moduledoc false

  use WebSockex

  @impl true
  def handle_connect(_conn, state), do: {:ok, state}

  @impl true
  def handle_frame(_frame, state), do: {:ok, state}
end
