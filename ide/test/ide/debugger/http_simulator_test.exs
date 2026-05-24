defmodule Ide.Debugger.HttpSimulatorTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.HttpSimulator

  @weather_decoder {:json_decoder,
                    {:field, "current",
                     {:json_decoder,
                      {:map, nil,
                       [
                         {:json_decoder, {:field, "temperature_2m", {:json_decoder, :float}}},
                         {:json_decoder,
                          {:field, "weather_code", {:json_decoder, {:and_then, nil, {:json_decoder, :int}}}}}
                       ]}}}}

  @weather_settings %{
    "temperatureC" => 18,
    "condition" => "rain",
    "humidityPercent" => 55,
    "pressureHpa" => 1010,
    "windKph" => 12
  }

  test "build_json_body synthesizes nested JSON from decoder paths" do
    assert %{
             "current" => %{
               "temperature_2m" => 18.0,
               "weather_code" => 61
             }
           } = HttpSimulator.build_json_body(@weather_decoder, @weather_settings)
  end

  test "simulated_response decodes through HttpExecutor with simulator weather" do
    command = %{
      "kind" => "http",
      "method" => "GET",
      "url" => "https://example.test/weather",
      "headers" => [],
      "body" => %{"kind" => "empty"},
      "expect" => %{
        "kind" => "json",
        "to_msg" => {:function_ref, "WeatherReceived"},
        "decoder" => {:json_decoder, {:field, "temperature", {:json_decoder, :float}}}
      }
    }

    context = %{simulator_weather: @weather_settings}

    assert {:ok, result} = Ide.Debugger.HttpExecutor.execute(command, context)

    assert result["message_value"] == %{
             "ctor" => "WeatherReceived",
             "args" => [%{"ctor" => "Ok", "args" => [18.0]}]
           }

    assert {:ok, %{"status" => 200, "body" => body}} =
             HttpSimulator.simulated_response(command, @weather_settings)

    assert Jason.decode!(body) == %{"temperature" => 18.0}
  end

  test "condition_weather_code maps simulator condition labels to Open-Meteo WMO codes" do
    assert HttpSimulator.condition_weather_code("clear") == 0
    assert HttpSimulator.condition_weather_code("cloudy") == 2
    assert HttpSimulator.condition_weather_code("fog") == 45
    assert HttpSimulator.condition_weather_code("drizzle") == 51
    assert HttpSimulator.condition_weather_code("rain") == 61
    assert HttpSimulator.condition_weather_code("snow") == 71
    assert HttpSimulator.condition_weather_code("showers") == 80
    assert HttpSimulator.condition_weather_code("storm") == 95
  end

  test "build_json_body maps cloudy simulator setting to Open-Meteo weather_code 2" do
    assert %{
             "current" => %{
               "temperature_2m" => 18.0,
               "weather_code" => 2
             }
           } =
             HttpSimulator.build_json_body(@weather_decoder, Map.put(@weather_settings, "condition", "cloudy"))
  end

  test "build_json_body maps snow simulator setting to Open-Meteo weather_code 71" do
    assert %{
             "current" => %{
               "temperature_2m" => 18.0,
               "weather_code" => 71
             }
           } =
             HttpSimulator.build_json_body(@weather_decoder, Map.put(@weather_settings, "condition", "snow"))
  end

  test "build_json_body handles Decode.map on leaf decoders inside fields" do
    decoder =
      {:json_decoder,
       {:field, "current",
        {:json_decoder,
         {:map, nil,
          [
            {:json_decoder, {:field, "temperature_2m", {:json_decoder, :float}}},
            {:json_decoder,
             {:field, "weather_code",
              {:json_decoder, {:map, nil, [{:json_decoder, :int}]}}}}
          ]}}}}

    assert %{
             "current" => %{
               "temperature_2m" => 21.0,
               "weather_code" => 0
             }
           } = HttpSimulator.build_json_body(decoder, %{"temperatureC" => 21, "condition" => "clear"})
  end
end
