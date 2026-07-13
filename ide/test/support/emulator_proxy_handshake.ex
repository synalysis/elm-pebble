defmodule Ide.TestSupport.EmulatorProxyHandshake do
  @moduledoc false

  alias Ide.Emulator.VncReady
  alias IdeWeb.EmulatorProxy.Types, as: ProxyTypes
  alias IdeWeb.EmulatorProxySocket

  @client_version "RFB 003.008\n"

  @type ws_send_failure ::
          {:stop, ProxyTypes.stop_reason(), EmulatorProxySocket.proxy_state()}

  @type proxy_error ::
          :banner_timeout
          | :tcp_response_timeout
          | :server_init_timeout
          | {:incomplete_banner, String.t()}
          | {:ws_send_failed, ws_send_failure()}

  @spec through_proxy(pos_integer(), timeout()) ::
          {:ok, {non_neg_integer(), non_neg_integer()}} | {:error, proxy_error()}
  def through_proxy(port, timeout \\ 5_000) when is_integer(port) and port > 0 do
    {:ok, state} = EmulatorProxySocket.init(%{target: {:tcp, "127.0.0.1", port}})

    with {:ok, state} <- await_banner(state, timeout),
         {:ok, state} <- send_ws(state, @client_version, timeout),
         {:ok, state, security} <- recv_ws(state, 2, timeout),
         true <- security_types_include_none?(security),
         {:ok, state} <- send_ws(state, <<1>>, timeout),
         {:ok, state, <<0, 0, 0, 0>>} <- recv_ws(state, 4, timeout),
         {:ok, state} <- send_ws(state, <<1>>, timeout),
         {:ok, width, height} <- recv_server_init(state, timeout) do
      {:ok, {width, height}}
    end
  end

  defp await_banner(state, timeout) do
    receive do
      {:tcp, socket, banner} when is_binary(banner) ->
        if VncReady.version_line_complete?(banner) do
          case EmulatorProxySocket.handle_info({:tcp, socket, banner}, state) do
            {:push, {:binary, _}, state} -> {:ok, state}
            {:ok, state} -> {:ok, state}
          end
        else
          {:error, {:incomplete_banner, banner}}
        end
    after
      timeout -> {:error, :banner_timeout}
    end
  end

  defp send_ws(state, data, _timeout) do
    case EmulatorProxySocket.handle_in({data, [opcode: :binary]}, state) do
      {:ok, state} -> {:ok, state}
      other -> {:error, {:ws_send_failed, other}}
    end
  end

  defp recv_ws(state, min_bytes, timeout) do
    receive do
      {:tcp, socket, data} when is_binary(data) and byte_size(data) >= min_bytes ->
        case EmulatorProxySocket.handle_info({:tcp, socket, data}, state) do
          {:push, {:binary, pushed}, state} -> {:ok, state, pushed}
          {:ok, state} -> {:ok, state, data}
        end
    after
      timeout -> {:error, :tcp_response_timeout}
    end
  end

  defp security_types_include_none?(<<count::unsigned-8, types::binary>>)
       when byte_size(types) >= count do
    1 in :binary.bin_to_list(binary_part(types, 0, count))
  end

  defp security_types_include_none?(_), do: false

  defp recv_server_init(state, timeout) do
    receive do
      {:tcp, socket, data} when is_binary(data) and byte_size(data) >= 24 ->
        case EmulatorProxySocket.handle_info({:tcp, socket, data}, state) do
          {:push, {:binary, _pushed}, _state} ->
            <<width::unsigned-big-16, height::unsigned-big-16, _::binary>> =
              binary_part(data, 0, 4)

            {:ok, width, height}

          {:ok, _state} ->
            <<width::unsigned-big-16, height::unsigned-big-16, _::binary>> =
              binary_part(data, 0, 4)

            {:ok, width, height}
        end
    after
      timeout -> {:error, :server_init_timeout}
    end
  end
end
