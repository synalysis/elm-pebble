defmodule Ide.Emulator.Session.Vnc do
  @moduledoc false

  alias Ide.Emulator.Types
  alias Ide.Emulator.VncReady

  @type state_slice :: %{
          required(:vnc_port) => pos_integer(),
          optional(:vnc_tcp) => port() | nil,
          optional(:vnc_tcp_buffer) => binary(),
          optional(:vnc_rfb_banner) => binary() | nil,
          optional(:vnc_banner_ready) => boolean()
        }

  @spec wait_for_tcp_port(pos_integer(), timeout()) :: :ok | {:error, Types.session_tuple_error()}
  def wait_for_tcp_port(port, timeout_ms) when is_integer(port) and is_integer(timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    wait_for_tcp_port_loop(port, deadline)
  end

  @spec capture_rfb_connection(pos_integer(), timeout()) ::
          {:ok, binary(), port()} | {:error, Types.session_tuple_error()}
  def capture_rfb_connection(port, timeout_ms) do
    case VncReady.capture_banner_open(port, timeout_ms) do
      {:ok, banner, tcp} -> {:ok, banner, tcp}
      {:error, reason} -> {:error, {:port_not_ready, :vnc_rfb, port, reason}}
    end
  end

  @spec reset_connection(state) :: state when state: Types.session_state()
  def reset_connection(state) do
    close_tcp_port(state.vnc_tcp)

    %{
      state
      | vnc_tcp: nil,
        vnc_tcp_buffer: <<>>,
        vnc_rfb_banner: nil,
        vnc_banner_ready: false
    }
  end

  @spec close_tcp_port(port() | nil) :: :ok
  def close_tcp_port(nil), do: :ok

  def close_tcp_port(tcp) when is_port(tcp) do
    :gen_tcp.close(tcp)
  end

  @spec append_tcp_buffer(Types.session_state(), binary()) :: Types.session_state()
  def append_tcp_buffer(%{vnc_tcp_buffer: buffer} = state, data) when is_binary(data) do
    %{state | vnc_tcp_buffer: buffer <> data}
  end

  defp wait_for_tcp_port_loop(port, deadline) do
    cond do
      Ide.Emulator.Session.ProcessHost.tcp_port_open?(port) ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        {:error, {:port_not_ready, :vnc, port}}

      true ->
        Process.sleep(50)
        wait_for_tcp_port_loop(port, deadline)
    end
  end
end
