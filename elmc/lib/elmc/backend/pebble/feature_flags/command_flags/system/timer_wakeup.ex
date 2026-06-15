defmodule Elmc.Backend.Pebble.FeatureFlags.CommandFlags.System.TimerWakeup do
  @moduledoc false

  alias Elmc.Backend.Pebble.FeatureFlags.TargetSet
  alias Elmc.Backend.Pebble.Types

  @spec compute(Types.call_target_set()) :: Types.command_timer_wakeup_flags()
  def compute(targets) do
    %{
      cmd_timer_after_ms: TargetSet.member?(targets, "Pebble.Cmd.timerAfter"),
      cmd_wakeup_schedule_after_seconds:
        TargetSet.member?(targets, "Pebble.Cmd.wakeupScheduleAfterSeconds"),
      cmd_wakeup_cancel: TargetSet.member?(targets, "Pebble.Cmd.wakeupCancel")
    }
  end
end
