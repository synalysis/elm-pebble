defmodule Elmc.Backend.Pebble.FeatureFlags.EventFlags.Platform do
  @moduledoc false

  alias Elmc.Backend.Pebble.FeatureFlags.EventFlags.Platform.{
    ConstructorEvents,
    SubscriptionEvents
  }

  alias Elmc.Backend.Pebble.Types

  @spec compute(Types.call_target_set(), Types.msg_constructor_list()) :: Types.event_platform_flags()
  def compute(targets, msg_constructors) do
    msg_constructors
    |> ConstructorEvents.compute()
    |> Map.merge(SubscriptionEvents.compute(targets))
  end
end
