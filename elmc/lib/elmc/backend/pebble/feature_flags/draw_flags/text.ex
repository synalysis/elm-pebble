defmodule Elmc.Backend.Pebble.FeatureFlags.DrawFlags.Text do
  @moduledoc false

  alias Elmc.Backend.Pebble.FeatureFlags.TargetSet
  alias Elmc.Backend.Pebble.Types

  @spec compute(Types.call_target_set()) :: Types.draw_text_flags()
  def compute(targets) do
    text_int = TargetSet.member?(targets, "Pebble.Ui.textInt")
    text_label = TargetSet.member?(targets, "Pebble.Ui.textLabel")

    %{
      draw_text_int: text_int,
      draw_text_label: text_label,
      draw_text: TargetSet.member?(targets, "Pebble.Ui.text"),
      draw_text_any: text_int or text_label or TargetSet.member?(targets, "Pebble.Ui.text")
    }
  end
end
