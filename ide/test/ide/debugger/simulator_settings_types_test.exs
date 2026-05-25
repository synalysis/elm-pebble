defmodule Ide.Debugger.SimulatorSettingsTypesTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger
  test "default_simulator_settings includes canonical weather and geolocation fields" do
    settings = Debugger.default_simulator_settings()

    assert is_integer(settings["battery_percent"])
    assert is_map(settings["weather"])
    assert is_binary(settings["timezone_id"])
    assert is_float(settings["latitude"])

    assert Map.has_key?(settings, "weather")
  end

  test "normalize_simulator_settings clamps battery percent" do
    normalized = Debugger.normalize_simulator_settings(%{"battery_percent" => 200})

    assert normalized["battery_percent"] == 100
  end
end
