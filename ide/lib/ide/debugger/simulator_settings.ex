defmodule Ide.Debugger.SimulatorSettings do
  @moduledoc """
  Canonical debugger simulator inputs and normalization.
  """

  alias Ide.Debugger.Types
  alias Ide.Debugger.WireValues

  @spec default() :: Types.simulator_settings()
  def default do
    %{
      "battery_percent" => 88,
      "charging" => false,
      "connected" => true,
      "clock_24h" => true,
      "use_simulated_time" => false,
      "simulated_time" => nil,
      "simulated_date" => nil,
      "timezone_id" => "Europe/Berlin",
      "timezone_offset_min" => 120,
      "locale" => "en-US",
      "language" => "en",
      "region" => "US",
      "network_online" => true,
      "notifications_enabled" => true,
      "quiet_hours" => false,
      "weather" => %{
        "temperatureC" => 21,
        "condition" => "clear",
        "humidityPercent" => 50,
        "pressureHpa" => 1013,
        "windKph" => 8
      },
      "calendar_events" => [],
      "storage_values" => %{},
      "preferences" => %{},
      "environment" => %{
        "sun" => %{"sunriseMin" => 420, "sunsetMin" => 1200, "polarDay" => false},
        "moon" => %{"moonriseMin" => 900, "moonsetMin" => 300, "phaseE6" => 500_000},
        "tide" => nil
      },
      "latitude" => 48.137154,
      "longitude" => 11.576124,
      "accuracy" => 25.0,
      "timeline_peek" => false,
      "compass_heading_deg" => 0,
      "compass_valid" => true,
      "app_in_focus" => true,
      "health_steps" => 4200,
      "health_steps_today" => 9100,
      "dictation_transcript" => "",
      "dictation_error" => "",
      "vibe_pattern_ms" => []
    }
  end

  @spec from_state(Types.runtime_state()) :: Types.simulator_settings()
  def from_state(state) when is_map(state) do
    state
    |> Map.get(:simulator_settings)
    |> normalize()
  end

  def from_state(_state), do: default()

  @spec from_model(Types.app_model()) :: Types.simulator_settings()
  def from_model(model) when is_map(model) do
    model
    |> WireValues.map_value("simulator_settings")
    |> normalize()
  end

  def from_model(_model), do: default()

  @spec normalize(Types.SimulatorSettings.wire_map()) :: Types.simulator_settings()
  def normalize(settings) when is_map(settings) do
    defaults = default()

    %{
      "battery_percent" =>
        settings
        |> WireValues.map_value("battery_percent")
        |> normalize_integer(defaults["battery_percent"])
        |> min(100)
        |> max(0),
      "charging" => normalize_boolean(WireValues.map_value(settings, "charging"), defaults["charging"]),
      "connected" => normalize_boolean(WireValues.map_value(settings, "connected"), defaults["connected"]),
      "clock_24h" => normalize_boolean(WireValues.map_value(settings, "clock_24h"), defaults["clock_24h"]),
      "use_simulated_time" =>
        normalize_boolean(
          WireValues.map_value(settings, "use_simulated_time"),
          defaults["use_simulated_time"]
        ),
      "simulated_time" =>
        normalize_optional_string(
          WireValues.map_value(settings, "simulated_time"),
          defaults["simulated_time"]
        ),
      "simulated_date" =>
        normalize_optional_string(
          WireValues.map_value(settings, "simulated_date"),
          defaults["simulated_date"]
        ),
      "timezone_id" =>
        normalize_string(WireValues.map_value(settings, "timezone_id"), defaults["timezone_id"]),
      "timezone_offset_min" =>
        settings
        |> WireValues.map_value("timezone_offset_min")
        |> normalize_integer(defaults["timezone_offset_min"]),
      "locale" => normalize_string(WireValues.map_value(settings, "locale"), defaults["locale"]),
      "language" => normalize_string(WireValues.map_value(settings, "language"), defaults["language"]),
      "region" => normalize_string(WireValues.map_value(settings, "region"), defaults["region"]),
      "network_online" =>
        normalize_boolean(WireValues.map_value(settings, "network_online"), defaults["network_online"]),
      "notifications_enabled" =>
        normalize_boolean(
          WireValues.map_value(settings, "notifications_enabled"),
          defaults["notifications_enabled"]
        ),
      "quiet_hours" =>
        normalize_boolean(WireValues.map_value(settings, "quiet_hours"), defaults["quiet_hours"]),
      "weather" =>
        normalize_weather_settings(WireValues.map_value(settings, "weather"), defaults["weather"]),
      "calendar_events" =>
        normalize_json_list(WireValues.map_value(settings, "calendar_events"), defaults["calendar_events"]),
      "storage_values" =>
        normalize_json_map(WireValues.map_value(settings, "storage_values"), defaults["storage_values"]),
      "preferences" =>
        normalize_json_map(WireValues.map_value(settings, "preferences"), defaults["preferences"]),
      "environment" =>
        normalize_json_map(WireValues.map_value(settings, "environment"), defaults["environment"]),
      "latitude" =>
        normalize_float(WireValues.map_value(settings, "latitude"), defaults["latitude"], -90.0, 90.0),
      "longitude" =>
        normalize_float(WireValues.map_value(settings, "longitude"), defaults["longitude"], -180.0, 180.0),
      "accuracy" =>
        normalize_float(WireValues.map_value(settings, "accuracy"), defaults["accuracy"], 0.0, 100_000.0),
      "timeline_peek" =>
        normalize_boolean(WireValues.map_value(settings, "timeline_peek"), defaults["timeline_peek"]),
      "compass_heading_deg" =>
        settings
        |> WireValues.map_value("compass_heading_deg")
        |> normalize_integer(defaults["compass_heading_deg"])
        |> min(360)
        |> max(0),
      "compass_valid" =>
        normalize_boolean(WireValues.map_value(settings, "compass_valid"), defaults["compass_valid"]),
      "app_in_focus" =>
        normalize_boolean(WireValues.map_value(settings, "app_in_focus"), defaults["app_in_focus"]),
      "health_steps" =>
        settings
        |> WireValues.map_value("health_steps")
        |> normalize_integer(defaults["health_steps"])
        |> max(0),
      "health_steps_today" =>
        settings
        |> WireValues.map_value("health_steps_today")
        |> normalize_integer(defaults["health_steps_today"])
        |> max(0),
      "dictation_transcript" =>
        normalize_string(
          WireValues.map_value(settings, "dictation_transcript"),
          defaults["dictation_transcript"]
        ),
      "dictation_error" =>
        normalize_string(WireValues.map_value(settings, "dictation_error"), defaults["dictation_error"]),
      "vibe_pattern_ms" =>
        normalize_json_list(WireValues.map_value(settings, "vibe_pattern_ms"), defaults["vibe_pattern_ms"])
    }
  end

  def normalize(_settings), do: default()

  @spec temperature_celsius(Types.SimulatorSettings.wire_map()) :: integer() | nil
  def temperature_celsius(weather) when is_map(weather) do
    weather
    |> Map.get("temperatureC", Map.get(weather, :temperatureC))
    |> temperature_scalar()
  end

  def temperature_celsius(_weather), do: nil

  @spec temperature_scalar(number() | String.t() | Types.protocol_ctor_value()) :: integer() | nil
  def temperature_scalar(value) when is_integer(value), do: value

  def temperature_scalar(value) when is_float(value),
    do: value |> Float.round() |> trunc()

  def temperature_scalar(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" ->
        nil

      String.contains?(trimmed, ".") ->
        case Float.parse(trimmed) do
          {parsed, ""} -> parsed |> Float.round() |> trunc()
          _ -> nil
        end

      true ->
        case Integer.parse(trimmed) do
          {parsed, ""} -> parsed
          _ -> nil
        end
    end
  end

  def temperature_scalar(%{"temperature" => temp}), do: temperature_scalar(temp)
  def temperature_scalar(_value), do: nil

  @spec normalize_integer(Types.wire_input(), integer()) :: integer()
  defp normalize_integer(value, _default) when is_integer(value), do: value

  defp normalize_integer(value, default) when is_binary(value) and is_integer(default) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> default
    end
  end

  defp normalize_integer(_value, default) when is_integer(default), do: default

  @spec normalize_boolean(Types.wire_input(), boolean()) :: boolean()
  defp normalize_boolean(values, default) when is_list(values),
    do: Enum.any?(values, &normalize_boolean(&1, default))

  defp normalize_boolean(value, _default) when is_boolean(value), do: value
  defp normalize_boolean("True", _default), do: true
  defp normalize_boolean("False", _default), do: false
  defp normalize_boolean("true", _default), do: true
  defp normalize_boolean("false", _default), do: false
  defp normalize_boolean(_value, default) when is_boolean(default), do: default

  defp normalize_string(value, _default) when is_binary(value) and value != "", do: value
  defp normalize_string(_value, default) when is_binary(default), do: default

  defp normalize_optional_string(value, _default) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(_value, default), do: default

  defp normalize_json_map(value, _default) when is_map(value), do: value
  defp normalize_json_map(_value, default) when is_map(default), do: default

  defp normalize_json_list(value, _default) when is_list(value), do: value
  defp normalize_json_list(_value, default) when is_list(default), do: default

  @spec normalize_weather_settings(Types.SimulatorSettings.wire_map() | nil, Types.SimulatorSettings.weather()) ::
          Types.SimulatorSettings.weather()
  defp normalize_weather_settings(value, default) when is_map(value) and is_map(default) do
    weather =
      value
      |> Map.take(["temperatureC", "condition", "humidityPercent", "pressureHpa", "windKph"])
      |> Enum.reject(fn {_key, setting_value} -> is_nil(setting_value) or setting_value == "" end)
      |> Map.new()

    weather =
      case temperature_celsius(weather) do
        nil -> Map.delete(weather, "temperatureC")
        temp -> Map.put(weather, "temperatureC", temp)
      end

    if map_size(weather) == 0, do: default, else: weather
  end

  defp normalize_weather_settings(_value, default) when is_map(default), do: default
  defp normalize_weather_settings(_value, _default), do: %{}

  defp normalize_float(value, _default, min_value, max_value) when is_float(value),
    do: value |> max(min_value) |> min(max_value)

  defp normalize_float(value, _default, min_value, max_value) when is_integer(value),
    do: value * 1.0 |> max(min_value) |> min(max_value)

  defp normalize_float(value, default, min_value, max_value) when is_binary(value) do
    case Float.parse(value) do
      {parsed, ""} -> parsed |> max(min_value) |> min(max_value)
      _ -> default
    end
  end

  defp normalize_float(_value, default, _min_value, _max_value), do: default
end
