defmodule IdeWeb.EmulatorProxySocket do
  @moduledoc false

  @behaviour WebSock

  @impl true
  def init(%{target: {:tcp, host, port}}) do
    case :gen_tcp.connect(String.to_charlist(host), port, [:binary, active: true], 5_000) do
      {:ok, socket} ->
        {:ok, %{client: nil, tcp: socket}}

      {:error, reason} ->
        send(self(), {:emulator_proxy_closed, reason})
        {:ok, %{client: nil, tcp: nil}}
    end
  end

  def init(%{target: url}) when is_binary(url), do: init(%{url: url})

  def init(%{url: url}) do
    owner = self()

    case IdeWeb.EmulatorProxyClient.start_link(url, owner) do
      {:ok, client} ->
        {:ok, %{client: client}}

      {:error, reason} ->
        send(self(), {:emulator_proxy_closed, reason})
        {:ok, %{client: nil}}
    end
  end

  @impl true
  def handle_in({data, [opcode: :binary]}, %{tcp: socket} = state) when is_port(socket) do
    _ = :gen_tcp.send(socket, data)
    {:ok, state}
  end

  def handle_in({data, [opcode: :text]}, %{tcp: socket} = state) when is_port(socket) do
    _ = :gen_tcp.send(socket, data)
    {:ok, state}
  end

  def handle_in({data, [opcode: :binary]}, state) do
    send_frame(state.client, {:binary, data})
    {:ok, state}
  end

  def handle_in({data, [opcode: :text]}, state) do
    send_frame(state.client, {:text, data})
    {:ok, state}
  end

  def handle_in(_message, state), do: {:ok, state}

  @impl true
  def handle_info({:emulator_proxy_frame, {:binary, data}}, state),
    do: {:push, {:binary, data}, state}

  def handle_info({:emulator_proxy_frame, {:text, data}}, state),
    do: {:push, {:text, data}, state}

  def handle_info({:tcp, socket, data}, %{tcp: socket} = state),
    do: {:push, {:binary, data}, state}

  def handle_info({:tcp_closed, socket}, %{tcp: socket} = state), do: {:stop, :normal, state}

  def handle_info({:tcp_error, socket, _reason}, %{tcp: socket} = state),
    do: {:stop, :normal, state}

  def handle_info({:emulator_proxy_closed, _reason}, state), do: {:stop, :normal, state}
  def handle_info(_message, state), do: {:ok, state}

  @impl true
  def terminate(_reason, state) do
    if is_port(state[:tcp]) do
      :gen_tcp.close(state.tcp)
    end

    if is_pid(state[:client]) do
      WebSockex.cast(state.client, :close)
    end

    :ok
  end

  defp send_frame(pid, frame) when is_pid(pid), do: WebSockex.send_frame(pid, frame)
  defp send_frame(_pid, _frame), do: :ok
end
