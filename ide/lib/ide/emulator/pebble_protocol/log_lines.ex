defmodule Ide.Emulator.PebbleProtocol.LogLines do
  @moduledoc false

  alias Ide.Emulator.PebbleProtocol.Packets

  @endpoint_system_log 0x07D2
  @endpoint_app_log 0x07D6
  @endpoint_app_run_state Packets.endpoint(:app_run_state)
  @endpoint_app_fetch Packets.endpoint(:app_fetch)
  @endpoint_put_bytes Packets.endpoint(:put_bytes)

  @app_log_levels %{
    0 => "DEBUG",
    50 => "INFO",
    100 => "WARNING",
    200 => "ERROR",
    250 => "ALWAYS"
  }

  @spec format_frame(map()) :: [String.t()]
  def format_frame(%{endpoint: endpoint, payload: payload}) when is_binary(payload) do
    cond do
      endpoint == @endpoint_put_bytes and putbytes_noise?(payload) ->
        []

      endpoint == @endpoint_app_log ->
        [format_app_log(payload)]

      endpoint == @endpoint_system_log ->
        format_system_log(payload)

      endpoint == @endpoint_app_run_state ->
        format_app_run_state(payload)

      endpoint == @endpoint_app_fetch ->
        [format_app_fetch(payload)]

      true ->
        []
    end
  end

  def format_frame(_frame), do: []

  @spec printable_strings(binary()) :: [String.t()]
  def printable_strings(binary) when is_binary(binary), do: printable_strings_impl(binary)

  @spec format_console(binary()) :: String.t()
  def format_console(data) when is_binary(data) do
    data
    |> String.split(~r/\r?\n/, trim: false)
    |> Enum.map(&String.trim_trailing/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  @spec fault_lines?([String.t()]) :: boolean()
  def fault_lines?(lines) when is_list(lines) do
    Enum.any?(lines, &fault_line?/1)
  end

  @spec fault_line?(String.t()) :: boolean()
  def fault_line?(line) when is_binary(line) do
    String.contains?(line, "App fault!") or
      (String.contains?(line, "PC:") and String.contains?(line, "LR:")) or
      String.contains?(line, "fault_handling")
  end

  defp putbytes_noise?(<<0x02, _cookie::32, _size::32, _payload::binary>>), do: true
  defp putbytes_noise?(<<0x02, _rest::binary>>), do: true
  defp putbytes_noise?(_), do: false

  defp format_app_log(payload) do
    if byte_size(payload) >= 40 do
      level = Map.get(@app_log_levels, :binary.at(payload, 20), "LOG")
      message_length = :binary.at(payload, 21)
      line = :binary.decode_unsigned(binary_part(payload, 22, 2), :big)
      filename = c_string(binary_part(payload, 24, 16))
      message = c_string(binary_part(payload, 40, message_length))
      source = if filename != "", do: "#{filename}:#{line}", else: "line=#{line}"

      "AppLog #{level} #{source}: #{message}"
    else
      strings = printable_strings(payload)

      if strings == [] do
        "AppLog #{hex_preview(payload)}"
      else
        "AppLog: #{Enum.join(strings, " | ")}"
      end
    end
  end

  defp format_system_log(payload) do
    strings = printable_strings(payload)

    cond do
      strings != [] ->
        Enum.map(strings, &("SystemLog: " <> &1))

      true ->
        ["SystemLog #{hex_preview(payload)}"]
    end
  end

  defp format_app_run_state(payload) do
    case payload do
      <<0x01, uuid::binary-size(16), _rest::binary>> ->
        ["AppRunState start uuid=#{format_uuid(uuid)}"]

      <<0x02, uuid::binary-size(16), _rest::binary>> ->
        ["AppRunState stop uuid=#{format_uuid(uuid)}"]

      <<0x03, _rest::binary>> ->
        ["AppRunState request"]

      <<opcode, _rest::binary>> ->
        ["AppRunState opcode=0x#{Integer.to_string(opcode, 16)} #{hex_preview(payload)}"]

      _ ->
        ["AppRunState #{hex_preview(payload)}"]
    end
  end

  defp format_app_fetch(payload) do
    "AppFetch #{hex_preview(payload)}"
  end

  defp c_string(binary) do
    binary
    |> :binary.split(<<0>>)
    |> List.first()
    |> to_string()
    |> String.trim()
  end

  defp printable_strings_impl(binary) when is_binary(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.chunk_by(fn byte -> byte in 32..126 end)
    |> Enum.filter(fn [first | _] -> first in 32..126 end)
    |> Enum.map(&:binary.list_to_bin/1)
    |> Enum.filter(&(String.length(&1) >= 4))
  end

  defp hex_preview(payload) do
    preview = binary_part(payload, 0, min(byte_size(payload), 24))
    hex = Base.encode16(preview, case: :lower)
    if byte_size(payload) > 24, do: hex <> "...", else: hex
  end

  defp format_uuid(<<a::32, b::16, c::16, d::16, e::48>>) do
    Enum.join(
      [
        Integer.to_string(a, 16) |> String.pad_leading(8, "0"),
        Integer.to_string(b, 16) |> String.pad_leading(4, "0"),
        Integer.to_string(c, 16) |> String.pad_leading(4, "0"),
        Integer.to_string(d, 16) |> String.pad_leading(4, "0"),
        Integer.to_string(e, 16) |> String.pad_leading(12, "0")
      ],
      "-"
    )
    |> String.downcase()
  end
end
