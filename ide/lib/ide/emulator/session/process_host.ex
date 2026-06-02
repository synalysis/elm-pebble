defmodule Ide.Emulator.Session.ProcessHost do
  @moduledoc false

  alias Ide.Emulator.Session.Qemu
  alias Ide.Emulator.Types

  @spec start_daemon(String.t(), [String.t()], String.t()) ::
          {:ok, pid()} | {:error, Types.session_tuple_error()}
  def start_daemon(command, args, prefix) do
    case MuonTrap.Daemon.start_link(command, args,
           log_output: :debug,
           log_prefix: prefix,
           stderr_to_stdout: true
         ) do
      {:ok, pid} -> {:ok, pid}
      {:error, reason} -> {:error, {:daemon_start_failed, command, reason}}
    end
  end

  @spec wait_for_daemon(pid(), pos_integer(), timeout()) ::
          :ok | {:error, Types.session_tuple_error()}
  def wait_for_daemon(pid, port, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    wait_for_daemon(pid, port, deadline, nil)
  end

  @spec wait_for_qemu_boot(pid(), pos_integer(), timeout()) ::
          :ok | {:error, Types.session_error()}
  def wait_for_qemu_boot(pid, console_port, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    markers = Qemu.boot_markers()

    with {:ok, socket} <- wait_for_tcp_socket(pid, console_port, deadline) do
      wait_for_qemu_boot_marker(pid, socket, deadline, <<>>, markers)
    end
  end

  @spec allocate_ports(pos_integer()) ::
          {:ok, [pos_integer()]} | {:error, Types.session_tuple_error()}
  def allocate_ports(count) do
    ports =
      Enum.map(1..count, fn _ ->
        {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
        {:ok, port} = :inet.port(socket)
        :gen_tcp.close(socket)
        port
      end)

    {:ok, ports}
  rescue
    error -> {:error, {:port_allocation_failed, error}}
  end

  @spec tcp_port_open?(pos_integer()) :: boolean()
  def tcp_port_open?(port) when is_integer(port) do
    case :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], 250) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _reason} ->
        false
    end
  end

  @spec cleanup_process(pid() | nil) :: :ok
  def cleanup_process(nil), do: :ok

  def cleanup_process(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      stop_process(pid, 1_000)
    else
      :ok
    end
  end

  @spec live_pid?(pid() | nil) :: boolean()
  def live_pid?(pid) when is_pid(pid), do: Process.alive?(pid)
  def live_pid?(_pid), do: false

  defp wait_for_daemon(pid, port, deadline, last_error) do
    cond do
      not Process.alive?(pid) ->
        {:error, {:daemon_exited_before_ready, port}}

      tcp_port_open?(port) ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        {:error, {:daemon_not_ready, port, last_error}}

      true ->
        Process.sleep(100)
        wait_for_daemon(pid, port, deadline, :not_ready)
    end
  end

  defp wait_for_tcp_socket(pid, port, deadline) do
    cond do
      not Process.alive?(pid) ->
        {:error, {:daemon_exited_before_ready, port}}

      System.monotonic_time(:millisecond) >= deadline ->
        {:error, {:daemon_not_ready, port, :not_ready}}

      true ->
        case :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], 250) do
          {:ok, socket} ->
            {:ok, socket}

          {:error, _reason} ->
            Process.sleep(100)
            wait_for_tcp_socket(pid, port, deadline)
        end
    end
  end

  defp wait_for_qemu_boot_marker(pid, socket, deadline, received, markers) do
    cond do
      boot_marker?(received, markers) ->
        :gen_tcp.close(socket)
        :ok

      not Process.alive?(pid) ->
        :gen_tcp.close(socket)
        {:error, :qemu_exited_before_boot}

      System.monotonic_time(:millisecond) >= deadline ->
        :gen_tcp.close(socket)

        reason =
          if Qemu.firmware_failure?(received) do
            {:qemu_boot_firmware_failure, Qemu.console_tail(received)}
          else
            {:qemu_boot_timeout, Qemu.console_tail(received)}
          end

        {:error, reason}

      true ->
        case :gen_tcp.recv(socket, 0, 250) do
          {:ok, data} ->
            wait_for_qemu_boot_marker(pid, socket, deadline, received <> data, markers)

          {:error, :timeout} ->
            wait_for_qemu_boot_marker(pid, socket, deadline, received, markers)

          {:error, reason} ->
            :gen_tcp.close(socket)
            {:error, {:qemu_console_closed, reason}}
        end
    end
  end

  defp boot_marker?(data, markers) do
    Enum.any?(markers, fn marker ->
      :binary.match(data, marker) != :nomatch
    end)
  end

  defp stop_process(pid, timeout) do
    GenServer.stop(pid, :normal, timeout)
    :ok
  catch
    :exit, _reason ->
      Process.exit(pid, :kill)
      wait_for_process_exit(pid, timeout)
  end

  defp wait_for_process_exit(pid, timeout) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    after
      timeout ->
        Process.demonitor(ref, [:flush])
        :ok
    end
  end
end
