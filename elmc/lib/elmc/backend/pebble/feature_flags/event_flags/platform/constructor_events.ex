defmodule Elmc.Backend.Pebble.FeatureFlags.EventFlags.Platform.ConstructorEvents do
  @moduledoc false

  alias Elmc.Backend.Pebble.FeatureFlags.EventFlags.Lookup
  alias Elmc.Backend.Pebble.Types

  @spec compute(Types.msg_constructor_list()) :: Types.event_constructor_platform_flags()
  def compute(msg_constructors) do
    %{
      battery_events:
        Lookup.has_any_constructor?(msg_constructors, [
          "BatteryLevelChanged",
          "BatteryChanged",
          "BatteryUpdate"
        ]),
      connection_events:
        Lookup.has_any_constructor?(msg_constructors, [
          "ConnectionStatusChanged",
          "ConnectionChanged",
          "BluetoothChanged"
        ])
    }
  end
end
