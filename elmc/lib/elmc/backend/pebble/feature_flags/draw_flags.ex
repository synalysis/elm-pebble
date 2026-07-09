defmodule Elmc.Backend.Pebble.FeatureFlags.DrawFlags do
  @moduledoc false

  alias Elmc.Backend.Pebble.FeatureFlags.DrawFlags.{Compact, Context, Primitives, Text}
  alias Elmc.Backend.Pebble.FeatureFlags.TargetSet
  alias Elmc.Backend.Pebble.Types

  @spec compute(Types.call_target_set()) :: Types.draw_feature_flags()
  def compute(targets) do
    context? =
      TargetSet.member?(targets, "Pebble.Ui.group") or
        TargetSet.member?(targets, "Pebble.Ui.context")

    flags =
      targets
      |> Primitives.compute()
      |> Map.merge(Context.compute(targets, context?))
      |> Map.merge(Text.compute(targets))

    Map.merge(flags, Compact.compute(flags))
  end
end
