defmodule Elmc.Backend.Pebble.FeatureFlags.CommandFlags.Services.Vibes do
  @moduledoc false

  alias Elmc.Backend.Pebble.FeatureFlags.TargetSet
  alias Elmc.Backend.Pebble.Types

  @spec compute(Types.call_target_set()) :: Types.command_vibes_flags()
  def compute(targets) do
    %{
      cmd_vibes_cancel:
        TargetSet.member?(targets, "Pebble.Cmd.vibesCancel") or
          TargetSet.member?(targets, "Pebble.Vibes.cancel"),
      cmd_vibes_short_pulse:
        TargetSet.member?(targets, "Pebble.Cmd.vibesShortPulse") or
          TargetSet.member?(targets, "Pebble.Vibes.shortPulse"),
      cmd_vibes_long_pulse:
        TargetSet.member?(targets, "Pebble.Cmd.vibesLongPulse") or
          TargetSet.member?(targets, "Pebble.Vibes.longPulse"),
      cmd_vibes_double_pulse:
        TargetSet.member?(targets, "Pebble.Cmd.vibesDoublePulse") or
          TargetSet.member?(targets, "Pebble.Vibes.doublePulse"),
      cmd_vibes_custom_pattern:
        TargetSet.member?(targets, "Pebble.Vibes.pattern") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.vibesCustomPattern")
    }
  end
end
