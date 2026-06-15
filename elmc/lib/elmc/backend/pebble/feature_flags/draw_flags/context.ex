defmodule Elmc.Backend.Pebble.FeatureFlags.DrawFlags.Context do
  @moduledoc false

  alias Elmc.Backend.Pebble.FeatureFlags.TargetSet
  alias Elmc.Backend.Pebble.Types

  @spec compute(Types.call_target_set(), boolean()) :: Types.draw_context_flags()
  def compute(targets, context?) do
    %{
      draw_context: context?,
      draw_stroke_width: context? and TargetSet.member?(targets, "Pebble.Ui.strokeWidth"),
      draw_antialiased: context? and TargetSet.member?(targets, "Pebble.Ui.antialiased"),
      draw_stroke_color: context? and TargetSet.member?(targets, "Pebble.Ui.strokeColor"),
      draw_fill_color: context? and TargetSet.member?(targets, "Pebble.Ui.fillColor"),
      draw_text_color: context? and TargetSet.member?(targets, "Pebble.Ui.textColor"),
      draw_compositing_mode: context? and TargetSet.member?(targets, "Pebble.Ui.compositingMode")
    }
  end
end
