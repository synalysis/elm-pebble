defmodule Elmc.Backend.Pebble.FeatureFlags.CommandFlags.Services.Health do
  @moduledoc false

  alias Elmc.Backend.Pebble.FeatureFlags.TargetSet
  alias Elmc.Backend.Pebble.Types

  @spec compute(Types.call_target_set()) :: Types.command_health_flags()
  def compute(targets) do
    %{
      cmd_health_value: TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.healthValue"),
      cmd_health_sum_today: TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.healthSumToday"),
      cmd_health_sum: TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.healthSum"),
      cmd_health_accessible: TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.healthAccessible"),
      cmd_health_supported:
        TargetSet.member?(targets, "Pebble.Health.supported") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.healthSupported")
    }
  end
end
