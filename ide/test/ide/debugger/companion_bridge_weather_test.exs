defmodule Ide.Debugger.CompanionBridgeWeatherTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.CompanionBridge

  test "weather_info fills missing Maybe fields as Nothing for elmx record access" do
    info = CompanionBridge.weather_info(%{"temperatureC" => 21, "condition" => "clear"})

    assert info["temperatureC"] == 21
    assert info["condition"] == %{"ctor" => "Clear", "args" => []}
    assert info["humidityPercent"] == %{"ctor" => "Nothing", "args" => []}
    assert info["pressureHpa"] == %{"ctor" => "Nothing", "args" => []}
    assert info["windKph"] == %{"ctor" => "Nothing", "args" => []}
    assert info["windDirectionDeg"] == %{"ctor" => "Nothing", "args" => []}
  end

  test "weather_info wraps present optional ints as Just" do
    info =
      CompanionBridge.weather_info(%{
        "temperatureC" => 18,
        "condition" => "rain",
        "pressureHpa" => 1013,
        "windKph" => 12
      })

    assert info["pressureHpa"] == %{"ctor" => "Just", "args" => [1013]}
    assert info["windKph"] == %{"ctor" => "Just", "args" => [12]}
    assert info["humidityPercent"] == %{"ctor" => "Nothing", "args" => []}
  end

  test "empty weather_info still provides required temperature and condition" do
    info = CompanionBridge.weather_info(nil)

    assert info["temperatureC"] == 0
    assert info["condition"] == %{"ctor" => "UnknownWeather", "args" => []}
    assert info["pressureHpa"] == %{"ctor" => "Nothing", "args" => []}
  end

  test "GotWeather subscription message embeds complete WeatherInfo under Current" do
    message =
      CompanionBridge.subscription_message_value(
        "weather",
        "GotWeather",
        "Ok",
        CompanionBridge.weather_info(%{"temperatureC" => 21, "condition" => "clear"})
      )

    assert %{
             "ctor" => "GotWeather",
             "args" => [
               %{
                 "ctor" => "Ok",
                 "args" => [
                   %{
                     "ctor" => "Current",
                     "args" => [info]
                   }
                 ]
               }
             ]
           } = message

    assert info["temperatureC"] == 21
    assert info["condition"] == %{"ctor" => "Clear", "args" => []}
    assert info["pressureHpa"] == %{"ctor" => "Nothing", "args" => []}
  end
end
