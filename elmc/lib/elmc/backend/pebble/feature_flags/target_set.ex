defmodule Elmc.Backend.Pebble.FeatureFlags.TargetSet do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec member?(Types.call_target_set(), Types.call_target()) :: boolean()
  def member?(targets, target), do: MapSet.member?(targets, target)
end
