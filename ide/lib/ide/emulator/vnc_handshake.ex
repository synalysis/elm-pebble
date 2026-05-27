defmodule Ide.Emulator.VncHandshake do
  @moduledoc false

  alias Ide.Emulator.Types

  @client_version "RFB 003.008\n"
  @connect_timeout 5_000

  @spec server_init(pos_integer(), timeout()) ::
          {:ok, {non_neg_integer(), non_neg_integer()}}
          | {:error, Types.vnc_error() | Types.screenshot_error()}
  def server_init(port, timeout \\ @connect_timeout) when is_integer(port) and port > 0 do
    with {:ok, socket} <-
           :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], @connect_timeout),
         {:ok, width, height} <- handshake(socket, timeout) do
      {:ok, {width, height}}
    end
  end

  defp handshake(socket, timeout) do
    try do
      with {:ok, server_version} <- recv_line(socket, timeout),
           true <- String.starts_with?(server_version, "RFB "),
           :ok <- :gen_tcp.send(socket, @client_version),
           {:ok, security} <- negotiate_security(socket, timeout),
           :ok <- security,
           :ok <- :gen_tcp.send(socket, <<1>>),
           {:ok, width, height, _pf} <- read_server_init(socket, timeout) do
        {:ok, width, height}
      else
        false -> {:error, :invalid_server_version}
        other -> other
      end
    after
      :gen_tcp.close(socket)
    end
  end

  defp negotiate_security(socket, timeout) do
    with {:ok, <<count::unsigned-8>>} <- recv_exact(socket, 1, timeout),
         true <- count > 0,
         {:ok, types} <- recv_exact(socket, count, timeout) do
      if 1 in :binary.bin_to_list(types) do
        :gen_tcp.send(socket, <<1>>)
        recv_security_result(socket, timeout)
      else
        {:error, :vnc_no_none_security}
      end
    end
  end

  defp recv_security_result(socket, timeout) do
    case recv_exact(socket, 4, timeout) do
      {:ok, <<0, 0, 0, 0>>} -> {:ok, :ok}
      {:ok, <<_::32>>} -> {:error, :vnc_security_failed}
      other -> other
    end
  end

  defp read_server_init(socket, timeout) do
    with {:ok, <<width::unsigned-big-16, height::unsigned-big-16, _pf::binary-size(16),
                  name_len::unsigned-big-32>>} <-
           recv_exact(socket, 24, timeout),
         {:ok, _name} <- recv_exact(socket, name_len, timeout) do
      {:ok, width, height, nil}
    end
  end

  defp recv_line(socket, timeout) do
    recv_line(socket, timeout, <<>>)
  end

  defp recv_line(socket, timeout, acc) do
    case :binary.match(acc, "\n") do
      {newline_pos, 1} ->
        line = binary_part(acc, 0, newline_pos)
        {:ok, line}

      :nomatch ->
        case recv_exact(socket, 1, timeout) do
          {:ok, <<char>>} -> recv_line(socket, timeout, acc <> <<char>>)
          other -> other
        end
    end
  end

  defp recv_exact(socket, size, timeout) do
    :gen_tcp.recv(socket, size, timeout)
  end
end
