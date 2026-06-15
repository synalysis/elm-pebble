defmodule Elmc.Backend.Pebble.FeatureFlags.CommandFlags.System.TimeTimezone do
  @moduledoc false

  alias Elmc.Backend.Pebble.FeatureFlags.TargetSet
  alias Elmc.Backend.Pebble.Types

  @spec compute(Types.call_target_set()) :: Types.command_time_timezone_flags()
  def compute(targets) do
    %{
      cmd_get_current_time_string: TargetSet.member?(targets, "Pebble.Cmd.getCurrentTimeString"),
      cmd_get_current_date_time:
        TargetSet.member?(targets, "Pebble.Cmd.getCurrentDateTime") or
          TargetSet.member?(targets, "Pebble.Time.currentDateTime") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.getCurrentDateTime"),
      cmd_get_clock_style_24h: TargetSet.member?(targets, "Pebble.Cmd.getClockStyle24h"),
      cmd_get_timezone_is_set: TargetSet.member?(targets, "Pebble.Cmd.getTimezoneIsSet"),
      cmd_get_timezone: TargetSet.member?(targets, "Pebble.Cmd.getTimezone")
    }
  end
end
