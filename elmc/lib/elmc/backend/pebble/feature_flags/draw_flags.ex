defmodule Elmc.Backend.Pebble.FeatureFlags.DrawFlags do
  @moduledoc false

  alias Elmc.Backend.Pebble.FeatureFlags.DrawFlags.{Context, Primitives, Text}
  alias Elmc.Backend.Pebble.FeatureFlags.TargetSet
  alias Elmc.Backend.Pebble.Types

  @spec compute(Types.call_target_set()) :: Types.draw_feature_flags()
  def compute(targets) do
    context? =
      TargetSet.member?(targets, "Pebble.Ui.group") or
        TargetSet.member?(targets, "Pebble.Ui.context")

    targets
    |> Primitives.compute()
    |> Map.merge(Context.compute(targets, context?))
    |> Map.merge(Text.compute(targets))
  end
end
