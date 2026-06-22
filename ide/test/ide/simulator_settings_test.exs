defmodule Ide.SimulatorSettingsTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.CompileContract
  alias Ide.SimulatorSettings

  defp watch_time_debugger_state do
    {:ok, watch} =
      CompileContract.analyze_source(
        """
        module Main exposing (main)

        import Pebble.Events as Events

        subscriptions _ =
            Events.onMinuteChange MinuteChanged
        """,
        "Main.elm"
      )

    %{watch: %{model: %{"debugger_contract" => Map.fetch!(watch, "debugger_contract")}}}
  end

  test "emulator mode hides debugger-only simulated time fields" do
    debugger_state = watch_time_debugger_state()

    keys =
      debugger_state
      |> then(&SimulatorSettings.active_groups(nil, &1, :emulator))
      |> Enum.flat_map(fn {_group, _title, fields} -> Enum.map(fields, & &1.key) end)

    refute "use_simulated_time" in keys
    refute "simulated_date" in keys
    refute "simulated_time" in keys
    assert "clock_24h" in keys
  end

  test "emulator mode shows simulator weather toggle in weather group" do
    phone_source = """
    module CompanionApp exposing (main)

    import Pebble.Companion.Weather as Weather

    subscriptions _ =
        Weather.onWeather GotWeather
    """

    {:ok, phone} = Ide.Debugger.CompileContract.analyze_source(phone_source, "CompanionApp.elm")
    debugger_state = %{phone: %{model: %{"debugger_contract" => Map.fetch!(phone, "debugger_contract")}}}

    keys =
      debugger_state
      |> then(&SimulatorSettings.active_groups(nil, &1, :emulator))
      |> Enum.flat_map(fn {_group, _title, fields} -> Enum.map(fields, & &1.key) end)

    assert "use_simulator_weather" in keys
    assert "weather_temperatureC" in keys
  end

  test "debugger mode includes simulated time fields when watch_time capability applies" do
    debugger_state = watch_time_debugger_state()

    keys =
      debugger_state
      |> then(&SimulatorSettings.active_groups(nil, &1, :debugger))
      |> Enum.flat_map(fn {_group, _title, fields} -> Enum.map(fields, & &1.key) end)

    assert "use_simulated_time" in keys
    assert "simulated_date" in keys
    assert "simulated_time" in keys
  end
end
