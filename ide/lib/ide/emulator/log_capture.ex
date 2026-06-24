defmodule Ide.Emulator.LogCapture do
  @moduledoc false

  alias Ide.Emulator.PebbleProtocol.{LogLines, Router}
  alias Ide.Emulator.Session.ProcessHost

  @type capture_context :: %{
          optional(:console_port) => pos_integer() | nil,
          optional(:protocol_router_pid) => pid() | nil
        }

  @type snapshot :: %{
          required(:source) => String.t(),
          required(:duration_ms) => pos_integer(),
          required(:output) => String.t(),
          required(:lines) => [String.t()],
          required(:fault_detected) => boolean(),
          required(:console) => %{required(:output) => String.t(), required(:error) => term() | nil},
          required(:protocol) => %{
            required(:lines) => [String.t()],
            required(:error) => term() | nil
          }
        }

  @default_duration_ms 5_000

  @spec snapshot(capture_context(), keyword()) :: snapshot()
  def snapshot(session_fields, opts \\ []) when is_map(session_fields) do
    duration_ms = parse_duration_ms(opts)
    console_port = Map.get(session_fields, :console_port)
    router_pid = Map.get(session_fields, :protocol_router_pid)

    console_task =
      Task.async(fn ->
        capture_console(console_port, duration_ms)
      end)

    {protocol_lines, protocol_error} =
      if ProcessHost.live_pid?(router_pid) do
        case Router.collect_inbound(router_pid, duration_ms) do
          {:ok, lines} -> {lines, nil}
          {:error, reason} -> {[], reason}
        end
      else
        {[], :embedded_protocol_router_not_started}
      end

    {console_output, console_error} =
      case Task.await(console_task, duration_ms + 5_000) do
        {:ok, output} -> {output, nil}
        {:error, reason} -> {"", reason}
      end

    console_output = sanitize_utf8(console_output)

    console_lines = extract_console_lines(console_output)
    protocol_lines = Enum.map(protocol_lines, &sanitize_utf8/1)
    lines = console_lines ++ protocol_lines
    output = format_output(console_lines, protocol_lines, console_error, protocol_error) |> sanitize_utf8()

    fault_detected =
      LogLines.fault_lines?(lines) or String.contains?(console_output, "App fault!")

    %{
      source: "embedded",
      duration_ms: duration_ms,
      output: output,
      lines: lines,
      fault_detected: fault_detected,
      console: %{output: console_output, error: console_error},
      protocol: %{lines: protocol_lines, error: protocol_error}
    }
  end

  @spec capture_console(pos_integer() | nil, pos_integer()) ::
          {:ok, String.t()} | {:error, term()}
  defp capture_console(port, _duration_ms) when not is_integer(port), do: {:ok, ""}

  defp capture_console(port, duration_ms) when is_integer(port) and port > 0 do
    deadline = System.monotonic_time(:millisecond) + duration_ms

    with {:ok, socket} <-
           :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], 5_000) do
      try do
        {:ok, recv_until(socket, deadline, <<>>)}
      after
        :gen_tcp.close(socket)
      end
    end
  end

  defp recv_until(socket, deadline, acc) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      acc
    else
      case :gen_tcp.recv(socket, 0, min(remaining, 500)) do
        {:ok, data} -> recv_until(socket, deadline, acc <> data)
        {:error, :timeout} -> recv_until(socket, deadline, acc)
        {:error, _} -> acc
      end
    end
  end

  defp format_output(console_lines, protocol_lines, console_error, protocol_error) do
    sections = []

    sections =
      if console_lines != [] do
        ["--- qemu console ---", Enum.join(console_lines, "\n") | sections]
      else
        sections
      end

    sections =
      if protocol_lines != [] do
        ["--- pebble protocol ---", Enum.join(protocol_lines, "\n") | sections]
      else
        sections
      end

    sections =
      case console_error do
        nil -> sections
        reason -> ["--- qemu console unavailable: #{inspect(reason)} ---" | sections]
      end

    sections =
      case protocol_error do
        nil -> sections
        reason -> ["--- pebble protocol unavailable: #{inspect(reason)} ---" | sections]
      end

    sections
    |> Enum.reverse()
    |> Enum.join("\n\n")
    |> String.trim()
  end

  @spec extract_console_lines(String.t()) :: [String.t()]
  defp extract_console_lines(console_output) do
    newline_lines =
      console_output
      |> LogLines.format_console()
      |> String.split("\n", trim: true)

    printable_lines =
      console_output
      |> LogLines.printable_strings()
      |> Enum.filter(&(String.length(&1) >= 8))

    interesting =
      Enum.filter(printable_lines, fn line ->
        String.starts_with?(line, ["NL:", "App fault", "fault_handling", "AppLog", "PC:"]) or
          String.contains?(line, "App fault!")
      end)

    (newline_lines ++ interesting)
    |> Enum.uniq()
    |> Enum.map(&sanitize_utf8/1)
  end

  @spec sanitize_utf8(String.t()) :: String.t()
  def sanitize_utf8(binary) when is_binary(binary) do
    case :unicode.characters_to_binary(binary, :utf8, :utf8) do
      sanitized when is_binary(sanitized) -> sanitized
      _ -> scrub_invalid_utf8(binary)
    end
  end

  defp scrub_invalid_utf8(binary) do
    for <<char::utf8 <- binary>>, into: "", do: <<char::utf8>>
  catch
    :error, _ -> printable_only(binary)
  end

  defp printable_only(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.map(fn
      byte when byte in [9, 10, 13] -> <<byte>>
      byte when byte in 32..126 -> <<byte>>
      _ -> "?"
    end)
    |> IO.iodata_to_binary()
  end

  defp parse_duration_ms(opts) do
    duration_ms =
      case Keyword.get(opts, :duration_ms) do
        ms when is_integer(ms) and ms > 0 -> ms
        _ -> nil
      end

    duration_ms =
      duration_ms ||
        case Keyword.get(opts, :logs_snapshot_seconds) do
          seconds when is_integer(seconds) and seconds > 0 -> seconds * 1_000
          _ -> nil
        end

    duration_ms = duration_ms || @default_duration_ms
    min(duration_ms, 30_000)
  end
end
