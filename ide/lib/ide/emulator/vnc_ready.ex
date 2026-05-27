defmodule Ide.Emulator.VncReady do
  @moduledoc false

  @connect_timeout 250
  @min_version_line_bytes 8

  @spec banner_ready?(pos_integer()) :: boolean()
  def banner_ready?(port) when is_integer(port) and port > 0 do
    wait_banner(port, 400) == :ok
  end

  @spec wait_banner(pos_integer(), timeout()) :: :ok | {:error, term()}
  def wait_banner(port, timeout_ms) when is_integer(port) and port > 0 and is_integer(timeout_ms) do
    case capture_banner(port, timeout_ms) do
      {:ok, _banner} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec capture_banner(pos_integer(), timeout()) :: {:ok, binary()} | {:error, term()}
  def capture_banner(port, timeout_ms) when is_integer(port) and port > 0 and is_integer(timeout_ms) do
    case capture_banner_open(port, timeout_ms) do
      {:ok, banner, socket} ->
        :gen_tcp.close(socket)
        {:ok, banner}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec capture_banner_open(pos_integer(), timeout()) ::
          {:ok, binary(), :gen_tcp.socket()} | {:error, term()}
  def capture_banner_open(port, timeout_ms)
      when is_integer(port) and port > 0 and is_integer(timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    case :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], @connect_timeout) do
      {:ok, socket} ->
        case capture_banner_loop(socket, deadline) do
          {:ok, banner} ->
            :inet.setopts(socket, active: false, nodelay: true, packet: :raw)
            {:ok, banner, socket}

          {:error, reason} ->
            :gen_tcp.close(socket)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, {:vnc_connect_failed, reason}}
    end
  end

  @doc """
  True when `acc` contains a complete RFB protocol-version line (ends with newline).
  """
  @spec version_line_complete?(binary()) :: boolean()
  def version_line_complete?(acc) when is_binary(acc) do
    case :binary.match(acc, "\n") do
      {newline_pos, _} ->
        line = binary_part(acc, 0, newline_pos)

        String.starts_with?(line, "RFB ") and byte_size(line) >= @min_version_line_bytes

      :nomatch ->
        false
    end
  end

  defp capture_banner_loop(socket, deadline, acc \\ <<>>) do
    cond do
      version_line_complete?(acc) ->
        {:ok, acc}

      System.monotonic_time(:millisecond) >= deadline ->
        {:error, :vnc_banner_timeout}

      true ->
        remaining = max(deadline - System.monotonic_time(:millisecond), 0)

        case :gen_tcp.recv(socket, 0, min(remaining, 50)) do
          {:ok, data} -> capture_banner_loop(socket, deadline, acc <> data)
          {:error, :timeout} -> capture_banner_loop(socket, deadline, acc)
          {:error, reason} -> {:error, {:vnc_probe_recv_failed, reason}}
        end
    end
  end
end
