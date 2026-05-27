defmodule IdeWeb.EmulatorProxyClient do
  @moduledoc false

  use WebSockex

  @spec start_link(String.t(), pid()) :: GenServer.on_start()
  def start_link(url, owner) when is_binary(url) and is_pid(owner) do
    # Do not block the browser upgrade on pypkjs/gevent accepting the upstream socket.
    case WebSockex.start_link(url, __MODULE__, %{owner: owner}, async_connect: true) do
      {:ok, pid} -> {:ok, pid}
      {:error, _} = error -> error
    end
  end

  @impl true
  def handle_frame({:binary, data}, state) do
    send(state.owner, {:emulator_proxy_frame, {:binary, data}})
    {:ok, state}
  end

  def handle_frame({:text, data}, state) do
    send(state.owner, {:emulator_proxy_frame, {:text, data}})
    {:ok, state}
  end

  @impl WebSockex
  def handle_connect(_conn, state) do
    send(state.owner, :emulator_proxy_upstream_connected)
    {:ok, state}
  end

  @impl true
  def handle_cast(:close, state), do: {:close, state}

  @impl true
  def terminate(reason, state) do
    send(state.owner, {:emulator_proxy_closed, reason})
    :ok
  end
end
