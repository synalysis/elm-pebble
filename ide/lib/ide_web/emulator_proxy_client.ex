defmodule IdeWeb.EmulatorProxyClient do
  @moduledoc false

  use WebSockex

  alias IdeWeb.EmulatorProxy.Types, as: ProxyTypes

  @type client_state :: %{required(:owner) => pid()}

  @spec start_link(String.t(), pid()) :: {:ok, pid()} | {:error, ProxyTypes.ws_start_error()}
  def start_link(url, owner) when is_binary(url) and is_pid(owner) do
    WebSockex.start_link(url, __MODULE__, %{owner: owner})
  end

  @impl true
  @spec handle_frame({:binary, binary()} | {:text, binary()}, client_state()) ::
          {:ok, client_state()}
  def handle_frame({:binary, data}, state) do
    send(state.owner, {:emulator_proxy_frame, {:binary, data}})
    {:ok, state}
  end

  def handle_frame({:text, data}, state) do
    send(state.owner, {:emulator_proxy_frame, {:text, data}})
    {:ok, state}
  end

  @impl WebSockex
  @spec handle_connect(map(), client_state()) :: {:ok, client_state()}
  def handle_connect(_conn, state) do
    send(state.owner, :emulator_proxy_upstream_connected)
    {:ok, state}
  end

  @impl true
  @spec handle_cast(:close, client_state()) :: {:close, client_state()}
  def handle_cast(:close, state), do: {:close, state}

  @impl true
  @spec terminate(ProxyTypes.terminate_reason(), client_state()) :: :ok
  def terminate(reason, state) do
    send(state.owner, {:emulator_proxy_closed, reason})
    :ok
  end
end
