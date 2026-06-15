defmodule Elmc.Backend.Pebble.FeatureFlags.CommandFlags.System.Backlight do
  @moduledoc false

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
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.backlight")
    }
  end
end
