defmodule Ide.Emulator.Session.VncHandlers do
  @moduledoc false

  alias Ide.Emulator.Session.Vnc
  alias Ide.Emulator.Types

  @spec local_port(Types.session_state()) :: {:reply, pos_integer(), Types.session_state()}
  def local_port(state), do: {:reply, state.vnc_port, state}

  @spec rfb_banner(Types.session_state()) ::
          {:reply, {:ok, binary()} | {:error, :not_ready}, Types.session_state()}
  def rfb_banner(%{vnc_rfb_banner: banner} = state) when is_binary(banner) do
    {:reply, {:ok, banner}, state}
  end

  def rfb_banner(state), do: {:reply, {:error, :not_ready}, state}

  @spec claim_tcp(Types.session_state()) ::
          {:reply, {:ok, port(), binary()} | {:error, atom()}, Types.session_state()}
  def claim_tcp(%{vnc_tcp: tcp} = state) when is_port(tcp) do
    buffer = Map.get(state, :vnc_tcp_buffer, <<>>)
    {:reply, {:ok, tcp, buffer}, %{state | vnc_tcp: nil, vnc_tcp_buffer: <<>>}}
  end

  def claim_tcp(state), do: {:reply, {:error, :vnc_tcp_unavailable}, state}

  @spec return_tcp(Types.session_state(), port()) :: {:reply, :ok, Types.session_state()}
  def return_tcp(%{vnc_tcp: nil} = state, tcp) when is_port(tcp) do
    :inet.setopts(tcp, active: true, nodelay: true, packet: :raw)
    {:reply, :ok, %{state | vnc_tcp: tcp}}
  end

  def return_tcp(state, tcp) when is_port(tcp) do
    :gen_tcp.close(tcp)
    {:reply, :ok, state}
  end

  @spec discard_tcp(Types.session_state()) :: {:reply, :ok, Types.session_state()}
  def discard_tcp(%{vnc_tcp: tcp} = state) when is_port(tcp) do
    :gen_tcp.close(tcp)
    {:reply, :ok, %{state | vnc_tcp: nil, vnc_tcp_buffer: <<>>}}
  end

  def discard_tcp(state), do: {:reply, :ok, state}

  @spec append_tcp_data(Types.session_state(), port(), binary()) ::
          {:noreply, Types.session_state()}
  def append_tcp_data(%{vnc_tcp: tcp} = state, tcp, data) when is_binary(data) do
    {:noreply, Vnc.append_tcp_buffer(state, data)}
  end
end
