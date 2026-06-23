defmodule Elmc.Backend.Pebble.FeatureFlags.CommandFlags.Services do
  @moduledoc false

  alias Elmc.Backend.Pebble.FeatureFlags.CommandFlags.Services.{
    DeviceServices,
    Health,
    Speaker,
    Vibes
  }

  alias Elmc.Backend.Pebble.Types

  @spec compute(Types.call_target_set()) :: Types.command_services_flags()
  def compute(targets) do
    targets
    |> Vibes.compute()
    |> Map.merge(Health.compute(targets))
    |> Map.merge(DeviceServices.compute(targets))
    |> Map.merge(Speaker.compute(targets))
  end
end
