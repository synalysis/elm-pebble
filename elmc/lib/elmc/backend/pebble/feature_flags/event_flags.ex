defmodule Elmc.Backend.Pebble.FeatureFlags.EventFlags do
  @moduledoc false

  alias Elmc.Backend.Pebble.FeatureFlags.EventFlags.{Clock, Input, Platform}
  alias Elmc.Backend.Pebble.Types

  @spec compute(Types.call_target_set(), Types.msg_constructor_list()) :: Types.event_feature_flags()
  def compute(targets, msg_constructors) do
    targets
    |> Clock.compute()
    |> Map.merge(Input.compute(targets, msg_constructors))
    |> Map.merge(Platform.compute(targets, msg_constructors))
  end
end
