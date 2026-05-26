defmodule Ide.Debugger.SimulatorWatchDeliveryTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.SimulatorWatchDelivery

  test "weather_message_value builds ProvideTemperature wire value" do
    assert SimulatorWatchDelivery.weather_message_value("ProvideTemperature", %{
             "temperatureC" => 21
           }) == %{
             "ctor" => "FromPhone",
             "args" => [
               %{
                 "ctor" => "ProvideTemperature",
                 "args" => [%{"ctor" => "Celsius", "args" => [21]}]
               }
             ]
           }
  end

  test "weather_step_message summarizes temperature" do
    assert SimulatorWatchDelivery.weather_step_message("ProvideTemperature", %{
             "temperatureC" => 3
           }) == "FromPhone (ProvideTemperature (Celsius 3))"
  end
end
