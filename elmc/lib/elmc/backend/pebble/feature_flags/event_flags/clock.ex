defmodule Elmc.Backend.Pebble.FeatureFlags.EventFlags.Clock do
  @moduledoc false

  alias Elmc.Backend.Pebble.FeatureFlags.TargetSet
  alias Elmc.Backend.Pebble.Types

  @spec compute(Types.call_target_set()) :: Types.event_clock_flags()
  def compute(targets) do
    uses_time_every =
      TargetSet.member?(targets, "Elm.Kernel.Time.every") or
        TargetSet.member?(targets, "Time.every")

    %{
      tick_events:
        uses_time_every or
          TargetSet.member?(targets, "Pebble.Events.onSecondChange") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.onSecondChange"),
      hour_events:
        TargetSet.member?(targets, "Pebble.Events.onHourChange") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.onHourChange"),
      minute_events:
        TargetSet.member?(targets, "Pebble.Events.onMinuteChange") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.onMinuteChange"),
      day_events:
        TargetSet.member?(targets, "Pebble.Events.onDayChange") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.onDayChange"),
      month_events:
        TargetSet.member?(targets, "Pebble.Events.onMonthChange") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.onMonthChange"),
      year_events:
        TargetSet.member?(targets, "Pebble.Events.onYearChange") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.onYearChange"),
      frame_events:
        TargetSet.member?(targets, "Pebble.Frame.every") or
          TargetSet.member?(targets, "Pebble.Frame.atFps") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.onFrame")
    }
  end
end
