defmodule Elmc.Backend.Pebble.FeatureFlags.CommandFlags do
  @moduledoc false

  alias Elmc.Backend.Pebble.FeatureFlags.CommandFlags.{Services, Storage, System}
  alias Elmc.Backend.Pebble.Types

  @spec compute(Types.call_target_set()) :: Types.command_feature_flags()
  def compute(targets) do
    targets
    |> Storage.compute()
    |> Map.merge(System.compute(targets))
    |> Map.merge(Services.compute(targets))
  end
end
