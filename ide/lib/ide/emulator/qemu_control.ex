defmodule Ide.Emulator.QemuControl do
  @moduledoc """
  Pebble QEMU control protocol: protocol IDs, payload encoders, and simulator-settings mapping.

  Shared by embedded HTTP control, external `pebble emu-*` CLI sync, and tests.
  """

  @protocol_tap 2
  @protocol_bluetooth 3
  @protocol_battery 5
  @protocol_button 8
  @protocol_time_format 9
  @protocol_timeline_peek 10
  @protocol_accel 11
  @protocol_compass 12

  alias Ide.Emulator.Types

  @type command :: %{required(:protocol) => non_neg_integer(), required(:payload) => binary()}

  @type external_cli_command :: %{required(:control) => String.t(), optional(String.t()) => String.t()}

  @doc """
  Control names exposed on the session API (browser toolbar / HTTP control).
  """
  @spec supported_controls() :: [String.t()]
  def supported_controls do
    ~w(
      button_up button_select button_down button_back
      tap battery bluetooth time_24h timeline_peek
      accel compass install logs screenshot
    )
  end

  @doc """
  Validates a QEMU control payload for the given protocol.
  """
  @spec validate_payload(non_neg_integer(), binary()) :: :ok | {:error, :invalid_qemu_payload}
  def validate_payload(@protocol_accel, payload) when byte_size(payload) == 6, do: :ok
  def validate_payload(@protocol_accel, _payload), do: {:error, :invalid_qemu_payload}

  def validate_payload(@protocol_compass, payload) when byte_size(payload) == 3, do: :ok
  def validate_payload(@protocol_compass, _payload), do: {:error, :invalid_qemu_payload}

  def validate_payload(_protocol, _payload), do: :ok

  @doc """
  Maps normalized simulator settings to QEMU control commands for embedded sessions.
  """
  @spec commands_from_simulator_settings(Types.simulator_settings()) :: [command()]
  def commands_from_simulator_settings(settings) when is_map(settings) do
    []
    |> maybe_battery_command(settings)
    |> maybe_bluetooth_command(settings)
    |> maybe_time_format_command(settings)
    |> maybe_timeline_peek_command(settings)
    |> maybe_compass_command(settings)
    |> Enum.reverse()
  end

  def commands_from_simulator_settings(_settings), do: []

  @doc """
  Maps simulator settings to Pebble CLI `emu-*` control params for external emulators.
  """
  @spec external_cli_commands(Types.simulator_settings()) :: [external_cli_command()]
  def external_cli_commands(settings) when is_map(settings) do
    []
    |> maybe_external_battery(settings)
    |> maybe_external_bluetooth(settings)
    |> maybe_external_time_format(settings)
    |> maybe_external_timeline_peek(settings)
    |> maybe_external_set_time(settings)
    |> maybe_external_compass(settings)
    |> Enum.reverse()
  end

  def external_cli_commands(_settings), do: []

  @spec encode_battery(non_neg_integer(), boolean()) :: command()
  def encode_battery(percent, charging) do
    %{
      protocol: @protocol_battery,
      payload: <<clamp_percent(percent), if(charging, do: 1, else: 0)>>
    }
  end

  @spec encode_bluetooth(boolean()) :: command()
  def encode_bluetooth(connected?) do
    %{protocol: @protocol_bluetooth, payload: <<if(connected?, do: 1, else: 0)>>}
  end

  @spec encode_time_format(boolean()) :: command()
  def encode_time_format(clock_24h?) do
    %{protocol: @protocol_time_format, payload: <<if(clock_24h?, do: 1, else: 0)>>}
  end

  @spec encode_timeline_peek(boolean()) :: command()
  def encode_timeline_peek(enabled?) do
    %{protocol: @protocol_timeline_peek, payload: <<if(enabled?, do: 1, else: 0)>>}
  end

  @spec encode_compass(non_neg_integer(), boolean()) :: command()
  def encode_compass(heading_deg, valid?) do
    deg = heading_deg |> max(0) |> min(360) |> round()
    %{protocol: @protocol_compass, payload: <<deg::16, if(valid?, do: 1, else: 0)>>}
  end

  @spec encode_accel(integer(), integer(), integer()) :: command()
  def encode_accel(x, y, z) do
    %{
      protocol: @protocol_accel,
      payload: <<signed_int16(x)::16-signed, signed_int16(y)::16-signed, signed_int16(z)::16-signed>>
    }
  end

  @spec encode_button(non_neg_integer()) :: command()
  def encode_button(button_state) when is_integer(button_state) and button_state >= 0 and button_state <= 255 do
    %{protocol: @protocol_button, payload: <<button_state>>}
  end

  @spec encode_tap() :: command()
  def encode_tap do
    %{protocol: @protocol_tap, payload: <<0, 1>>}
  end

  defp maybe_battery_command(commands, settings) do
    if Map.has_key?(settings, "battery_percent") or Map.has_key?(settings, "charging") do
      [encode_battery(Map.get(settings, "battery_percent", 88), Map.get(settings, "charging", false)) | commands]
    else
      commands
    end
  end

  defp maybe_bluetooth_command(commands, settings) do
    if Map.has_key?(settings, "connected") do
      [encode_bluetooth(Map.get(settings, "connected", false)) | commands]
    else
      commands
    end
  end

  defp maybe_time_format_command(commands, settings) do
    if Map.has_key?(settings, "clock_24h") do
      [encode_time_format(Map.get(settings, "clock_24h", false)) | commands]
    else
      commands
    end
  end

  defp maybe_timeline_peek_command(commands, settings) do
    if Map.has_key?(settings, "timeline_peek") do
      [encode_timeline_peek(Map.get(settings, "timeline_peek", false)) | commands]
    else
      commands
    end
  end

  defp maybe_external_battery(commands, settings) do
    if Map.has_key?(settings, "battery_percent") or Map.has_key?(settings, "charging") do
      [
        %{
          "control" => "battery",
          "percent" => Integer.to_string(Map.get(settings, "battery_percent", 0)),
          "charging" => bool_string(Map.get(settings, "charging", false))
        }
        | commands
      ]
    else
      commands
    end
  end

  defp maybe_external_bluetooth(commands, settings) do
    if Map.has_key?(settings, "connected") do
      [
        %{"control" => "bluetooth", "connected" => bool_string(Map.get(settings, "connected", false))}
        | commands
      ]
    else
      commands
    end
  end

  defp maybe_external_time_format(commands, settings) do
    if Map.has_key?(settings, "clock_24h") do
      [%{"control" => "time_format", "enabled" => bool_string(Map.get(settings, "clock_24h", false))} | commands]
    else
      commands
    end
  end

  defp maybe_external_timeline_peek(commands, settings) do
    if Map.has_key?(settings, "timeline_peek") do
      [
        %{"control" => "timeline_quick_view", "enabled" => bool_string(Map.get(settings, "timeline_peek", false))}
        | commands
      ]
    else
      commands
    end
  end

  defp maybe_external_set_time(commands, settings) do
    if simulated_time_enabled?(settings) do
      {:ok, time} = external_set_time_value(settings)
      [%{"control" => "set_time", "time" => time} | commands]
    else
      commands
    end
  end

  defp maybe_external_compass(commands, settings) do
    if Map.has_key?(settings, "compass_heading_deg") or Map.has_key?(settings, "compass_valid") do
      heading = Map.get(settings, "compass_heading_deg", 0) |> max(0) |> min(360) |> round()
      valid? = Map.get(settings, "compass_valid", true)

      [
        %{
          "control" => "compass",
          "heading" => Integer.to_string(heading),
          "valid" => bool_string(valid?)
        }
        | commands
      ]
    else
      commands
    end
  end

  defp simulated_time_enabled?(settings) do
    Map.get(settings, "use_simulated_time") in [true, "true", "1", 1]
  end

  defp external_set_time_value(settings) do
    fallback = NaiveDateTime.local_now()
    date = parse_simulated_date(Map.get(settings, "simulated_date"), NaiveDateTime.to_date(fallback))
    time = parse_simulated_time(Map.get(settings, "simulated_time"), NaiveDateTime.to_time(fallback))

    {:ok, naive} = NaiveDateTime.new(date, time)
    {:ok, Calendar.strftime(naive, "%H:%M:%S")}
  end

  defp parse_simulated_date(value, fallback) when is_binary(value) do
    case Date.from_iso8601(String.trim(value)) do
      {:ok, date} -> date
      {:error, _} -> fallback
    end
  end

  defp parse_simulated_date(_value, fallback), do: fallback

  defp parse_simulated_time(value, fallback) when is_binary(value) do
    case Time.from_iso8601(String.trim(value)) do
      {:ok, time} -> time
      {:error, _} -> fallback
    end
  end

  defp parse_simulated_time(_value, fallback), do: fallback

  defp maybe_compass_command(commands, settings) do
    if Map.has_key?(settings, "compass_heading_deg") or Map.has_key?(settings, "compass_valid") do
      [
        encode_compass(Map.get(settings, "compass_heading_deg", 0), Map.get(settings, "compass_valid", true))
        | commands
      ]
    else
      commands
    end
  end

  defp clamp_percent(percent) when is_integer(percent), do: percent |> max(0) |> min(100)
  defp clamp_percent(percent) when is_float(percent), do: percent |> round() |> clamp_percent()
  defp clamp_percent(_percent), do: 0

  defp signed_int16(value) when is_integer(value), do: value |> max(-32_768) |> min(32_767)

  defp bool_string(true), do: "true"
  defp bool_string(false), do: "false"
  defp bool_string(value) when value in ["true", "1", 1], do: "true"
  defp bool_string(_value), do: "false"
end
