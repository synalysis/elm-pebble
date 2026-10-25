defmodule Elmc.Backend.Pebble.FeatureFlags.CommandFlags.System.Backlight do
  @moduledoc false
  alias Elmc.Types, as: Types

  alias Elmc.Backend.Pebble.FeatureFlags.TargetSet
  alias Elmc.Backend.Pebble.Types

  @spec compute(Types.call_target_set()) :: Types.command_backlight_flags()
  def compute(targets) do
    %{
      cmd_backlight:
        TargetSet.member?(targets, "Pebble.Cmd.backlight") or
          TargetSet.member?(targets, "Pebble.Light.interaction") or
          TargetSet.member?(targets, "Pebble.Light.disable") or
          TargetSet.member?(targets, "Pebble.Light.enable") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.backlight"),
      cmd_backlight_color:
        TargetSet.member?(targets, "Pebble.Light.setColor") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.backlightColor"),
      cmd_backlight_reset_color:
        TargetSet.member?(targets, "Pebble.Light.resetColor") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.backlightResetColor"),
      cmd_backlight_rgb888:
        TargetSet.member?(targets, "Pebble.Light.setRgb") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.backlightRgb888")
    }
  end
end
