defmodule Elmc.Backend.Pebble.FeatureFlags.CommandFlags.System.DeviceQueries do
  @moduledoc false

  alias Elmc.Backend.Pebble.FeatureFlags.TargetSet
  alias Elmc.Backend.Pebble.Types

  @spec compute(Types.call_target_set()) :: Types.command_device_query_flags()
  def compute(targets) do
    %{
      cmd_get_battery_level:
        TargetSet.member?(targets, "Pebble.System.batteryLevel") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.getBatteryLevel"),
      cmd_get_connection_status:
        TargetSet.member?(targets, "Pebble.System.connectionStatus") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.getConnectionStatus"),
      cmd_get_watch_model: TargetSet.member?(targets, "Pebble.Cmd.getWatchModel"),
      cmd_get_watch_color: TargetSet.member?(targets, "Pebble.Cmd.getWatchColor"),
      cmd_get_firmware_version: TargetSet.member?(targets, "Pebble.Cmd.getFirmwareVersion")
    }
  end
end
