defmodule IdeWeb.EmulatorProxySocket do
  @moduledoc false

  @behaviour WebSock

  require Logger

  @type init_arg :: %{:target => {:tcp, String.t(), char()} | String.t()} | %{:url => String.t()}

  @type proxy_state :: %{
          optional(:client) => pid() | nil,
          optional(:tcp) => port() | nil,
          optional(:relay_logged) => boolean()
        }

  @impl true
  @spec init(init_arg()) :: {:ok, proxy_state()} | {:stop, term(), proxy_state()}
  def init(%{target: {:tcp, host, port}}) do
    case :gen_tcp.connect(String.to_charlist(host), port, [:binary, active: false], 5_000) do
      {:ok, socket} ->
        :inet.setopts(socket, active: true, nodelay: true, packet: :raw)

        {:ok, %{client: nil, tcp: socket, relay_logged: false}}

      {:error, reason} ->
        Logger.warning(
          "embedded emulator proxy tcp connect failed #{host}:#{port}: #{inspect(reason)}"
        )

        {:stop, {:tcp_connect_failed, reason}, %{client: nil, tcp: nil}}
    end
  end

  def init(%{target: url}) when is_binary(url), do: init_url(url)
  def init(%{url: url}) when is_binary(url), do: init_url(url)

  @spec init_url(String.t()) ::
          {:ok, proxy_state()} | {:stop, {:ws_connect_failed, term()}, proxy_state()}
  defp init_url(url) when is_binary(url) do
    owner = self()

    case IdeWeb.EmulatorProxyClient.start_link(url, owner) do
      {:ok, client} ->
        {:ok, %{client: client}}

      {:error, reason} ->
        {:stop, {:ws_connect_failed, reason}, %{client: nil, tcp: nil}}
    end
  end

  @impl true
  def handle_in({data, [opcode: :binary]}, %{tcp: socket} = state) when is_port(socket) do
    case :gen_tcp.send(socket, data) do
      :ok -> {:ok, state}
      {:error, reason} -> {:stop, {:tcp_send_failed, reason}, state}
    end
  end

  def handle_in({data, [opcode: :text]}, %{tcp: socket} = state) when is_port(socket) do
    case :gen_tcp.send(socket, data) do
      :ok -> {:ok, state}
      {:error, reason} -> {:stop, {:tcp_send_failed, reason}, state}
    end
  end

  def handle_in({data, [opcode: :binary]}, %{client: client} = state) when is_pid(client) do
    send_frame(client, {:binary, data})
    {:ok, state}
  end

  def handle_in({data, [opcode: :text]}, %{client: client} = state) when is_pid(client) do
    send_frame(client, {:text, data})
    {:ok, state}
  end

  def handle_in(_message, state), do: {:ok, state}

  @impl true
  def handle_info({:tcp, socket, data}, %{tcp: socket} = state) when is_binary(data) do
    state =
      if state[:relay_logged] do
        state
      else
        Logger.debug(
          "embedded emulator vnc proxy relayed first #{byte_size(data)} bytes to websocket"
        )

        %{state | relay_logged: true}
      end

    {:push, {:binary, data}, state}
  end

  def handle_info({:tcp_closed, socket}, %{tcp: socket} = state) do
    {:stop, :normal, state}
  end

  def handle_info({:tcp_error, socket, _reason}, %{tcp: socket} = state) do
    {:stop, :normal, state}
  end

  def handle_info({:emulator_proxy_frame, {:binary, data}}, state),
    do: {:push, {:binary, data}, state}

  def handle_info({:emulator_proxy_frame, {:text, data}}, state),
    do: {:push, {:text, data}, state}

  def handle_info({:emulator_proxy_closed, _reason}, state), do: {:stop, :normal, state}
  def handle_info(_message, state), do: {:ok, state}

  @impl true
  @spec terminate(term(), proxy_state()) :: :ok
  def terminate(_reason, state) do
    if is_port(state[:tcp]) do
      :gen_tcp.close(state.tcp)
    end

    if is_pid(state[:client]) do
      WebSockex.cast(state.client, :close)
    end

    :ok
  end

  @spec send_frame(pid(), {:binary | :text, binary()}) :: :ok
  defp send_frame(pid, frame) when is_pid(pid), do: WebSockex.send_frame(pid, frame)
end
