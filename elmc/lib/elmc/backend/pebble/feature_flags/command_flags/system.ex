defmodule Elmc.Backend.Pebble.FeatureFlags.CommandFlags.System do
  @moduledoc false

  alias Elmc.Backend.Pebble.FeatureFlags.CommandFlags.System.{
    Backlight,
    DeviceQueries,
    Logging,
    TimeTimezone,
    TimerWakeup
  }

  alias Elmc.Backend.Pebble.Types

  @spec compute(Types.call_target_set()) :: Types.command_system_flags()
  def compute(targets) do
    targets
    |> TimerWakeup.compute()
    |> Map.merge(Backlight.compute(targets))
    |> Map.merge(TimeTimezone.compute(targets))
    |> Map.merge(DeviceQueries.compute(targets))
    |> Map.merge(Logging.compute(targets))
  end
end
