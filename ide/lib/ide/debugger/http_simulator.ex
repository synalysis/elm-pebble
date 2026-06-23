defmodule Ide.Debugger.HttpSimulator do
  @moduledoc false

  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.SimulatorSettings

  @type json_decoder :: tuple() | atom() | list()

  @type json_leaf :: Types.wire_scalar() | Types.wire_map() | [json_leaf()]

  @type weather_map :: SimulatorSettings.weather() | Types.wire_map()

  @spec simulated_response(Types.TrackedHttpCommand.wire_map(), Types.simulator_settings() | nil) ::
          {:ok, Types.http_simulated_response()} | :skip
  def simulated_response(
        %{"expect" => %{"kind" => "json", "decoder" => decoder}} = _command,
        weather
      )
      when is_map(weather) and map_size(weather) > 0 and not is_nil(decoder) do
    simulate_json_body(decoder, weather)
  end

  def simulated_response(
        %{"expect" => %{"kind" => "json"}} = _command,
        weather
      )
      when is_map(weather) and map_size(weather) > 0 do
    simulate_json_body(nil, weather)
  end

  def simulated_response(_command, _weather), do: :skip

  @spec simulate_json_body(json_decoder() | function() | nil, weather_map()) ::
          {:ok, Types.http_simulated_response()} | :skip
  defp simulate_json_body(decoder, weather) when is_map(weather) do
    body = json_body_from_decoder(decoder, weather)

    case body do
      body when is_map(body) and map_size(body) > 0 ->
        {:ok, %{"status" => 200, "body" => Jason.encode!(body)}}

      _ ->
        :skip
    end
  end

  defp json_body_from_decoder(decoder, weather) when is_map(weather) do
    cond do
      match?({:json_decoder, _}, decoder) ->
        case build_json_body(decoder, weather) do
          body when is_map(body) and map_size(body) > 0 -> body
          _ -> open_meteo_current_forecast_body(weather)
        end

      function_decoder?(decoder) or is_nil(decoder) ->
        open_meteo_current_forecast_body(weather)

      true ->
        open_meteo_current_forecast_body(weather)
    end
  end

  @spec open_meteo_current_forecast_body(weather_map()) :: json_object()
  def open_meteo_current_forecast_body(weather) when is_map(weather) do
    %{
      "current" => %{
        "temperature_2m" => float_value("temperature_2m", weather),
        "weather_code" => condition_weather_code(Map.get(weather, "condition"))
      }
    }
  end

  defp function_decoder?(decoder), do: is_function(decoder, 1)

  @type json_object :: %{optional(String.t()) => json_leaf()}

  @spec build_json_body(json_decoder(), weather_map()) :: json_object()
  def build_json_body(decoder, weather) when is_map(weather) do
    decoder_object(decoder, weather)
  end

  def build_json_body(_decoder, _weather), do: %{}

  @leaf_types [:float, :int, :string, :bool, :value]

  defp decoder_object({:json_decoder, {:field, field, inner}}, weather) when is_binary(field) do
    case decoder_object(inner, weather) do
      %{} = nested when map_size(nested) == 0 -> %{}
      value when is_map(value) -> %{field => value}
      value -> %{field => value}
    end
  end

  defp decoder_object({:json_decoder, {:map, _fun, decoders}}, weather) when is_list(decoders) do
    results = Enum.map(decoders, &decoder_object(&1, weather))
    merged = merge_objects(results)

    case {merged, results} do
      {%{} = empty, [single]} when map_size(empty) == 0 and not is_map(single) ->
        single

      _ ->
        merged
    end
  end

  defp decoder_object({:json_decoder, {:map, _fun, inner}}, weather),
    do: decoder_object(inner, weather)

  defp decoder_object({:json_decoder, {:map_n, _fun, decoders}}, weather) when is_list(decoders) do
    results =
      Enum.map(decoders, fn
        {:json_decoder, inner} -> decoder_object(inner, weather)
        inner -> decoder_object(inner, weather)
      end)

    merge_objects(results)
  end

  defp decoder_object({:json_decoder, {:and_then, _fun, inner}}, weather),
    do: decoder_object(inner, weather)

  defp decoder_object({:json_decoder, {:list, inner}}, weather) do
    [decoder_object(inner, weather)]
  end

  defp decoder_object({:json_decoder, {:array, inner}}, weather) do
    [decoder_object(inner, weather)]
  end

  defp decoder_object({:json_decoder, {:index, _index, inner}}, weather),
    do: decoder_object(inner, weather)

  defp decoder_object({:json_decoder, {:succeed, value}}, _weather), do: value

  defp decoder_object({:json_decoder, type}, weather) when type in @leaf_types,
    do: leaf_value(nil, type, weather)

  defp decoder_object(_decoder, _weather), do: %{}

  defp merge_objects(objects) when is_list(objects) do
    Enum.reduce(objects, %{}, fn
      object, acc when is_map(object) -> Map.merge(acc, object)
      _other, acc -> acc
    end)
  end

  @spec leaf_value(String.t() | nil, atom(), weather_map()) :: json_leaf()
  defp leaf_value(field, :float, weather), do: float_value(field, weather)
  defp leaf_value(field, :int, weather), do: int_value(field, weather)

  defp leaf_value(_field, :string, weather),
    do: to_string(Map.get(weather, "condition") || "clear")

  defp leaf_value(_field, :bool, _weather), do: true
  defp leaf_value(_field, :value, weather), do: weather

  defp float_value(field, weather) do
    value =
      cond do
        field in ["temperature_2m", "temperature", "temperatureC"] ->
          Map.get(weather, "temperatureC") || 0

        field in ["relative_humidity_2m", "humidity", "humidityPercent"] ->
          Map.get(weather, "humidityPercent") || 0

        field in ["surface_pressure", "pressure", "pressureHpa"] ->
          Map.get(weather, "pressureHpa") || 0

        field in ["wind_speed_10m", "wind", "windKph"] ->
          Map.get(weather, "windKph") || 0

        true ->
          Map.get(weather, "temperatureC") || 0
      end

    to_float(value)
  end

  defp int_value(field, weather) do
    cond do
      field in ["weather_code", "condition_code", "condition"] ->
        condition_weather_code(Map.get(weather, "condition"))

      field in ["relative_humidity_2m", "humidity", "humidityPercent"] ->
        Map.get(weather, "humidityPercent") || 0

      field in ["surface_pressure", "pressure", "pressureHpa"] ->
        Map.get(weather, "pressureHpa") || 0

      field in ["wind_speed_10m", "wind", "windKph"] ->
        Map.get(weather, "windKph") || 0

      true ->
        condition_weather_code(Map.get(weather, "condition"))
    end
  end

  @spec condition_weather_code(String.t() | atom() | nil) :: integer()
  def condition_weather_code(condition) do
    # Open-Meteo WMO weather_code values for simulated HTTP JSON bodies.
    # Companion apps decode these with openMeteoConditionFromCode, not protocol wire codes.
    case to_string(condition || "clear") |> String.downcase() do
      "clear" -> 0
      "cloudy" -> 2
      "fog" -> 45
      "drizzle" -> 51
      "rain" -> 61
      "snow" -> 71
      "showers" -> 80
      "storm" -> 95
      _ -> 0
    end
  end

  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value * 1.0

  defp to_float(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {float, _} -> float
      :error -> 0.0
    end
  end

  defp to_float(_value), do: 0.0
end
