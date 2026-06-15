defmodule Elmc.Backend.Pebble.FeatureFlags.CommandFlags.Services.DeviceServices do
  @moduledoc false

  alias Elmc.Backend.Pebble.FeatureFlags.TargetSet
  alias Elmc.Backend.Pebble.Types

  @spec compute(Types.call_target_set()) :: Types.command_device_services_flags()
  def compute(targets) do
    %{
      cmd_data_log_bytes:
        TargetSet.member?(targets, "Pebble.DataLog.logBytes") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.dataLogBytes"),
      cmd_data_log_int32:
        TargetSet.member?(targets, "Pebble.DataLog.logInt32") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.dataLogInt32"),
      cmd_compass_peek:
        TargetSet.member?(targets, "Pebble.Compass.current") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.compassCurrent"),
      cmd_dictation_start:
        TargetSet.member?(targets, "Pebble.Dictation.start") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.dictationStart"),
      cmd_dictation_stop:
        TargetSet.member?(targets, "Pebble.Dictation.stop") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.dictationStop"),
      cmd_unobstructed_bounds_peek:
        TargetSet.member?(targets, "Pebble.UnobstructedArea.currentBounds") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.unobstructedCurrentBounds")
    }
  end
end
