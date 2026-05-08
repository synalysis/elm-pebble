defmodule IdeWeb.EmulatorProxySocket do
  @moduledoc false

  @behaviour WebSock

  @impl true
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

  def handle_info({:emulator_proxy_closed, _reason}, state), do: {:stop, :normal, state}
  def handle_info(_message, state), do: {:ok, state}

  @impl true
  def terminate(_reason, state) do
    if is_pid(state[:client]) do
      WebSockex.cast(state.client, :close)
    end

    :ok
  end

  defp send_frame(pid, frame) when is_pid(pid), do: WebSockex.send_frame(pid, frame)
  defp send_frame(_pid, _frame), do: :ok
end
