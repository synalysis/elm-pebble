defmodule Elmc.Backend.Pebble.FeatureFlags.DrawFlags.Primitives do
  @moduledoc false

  alias Elmc.Backend.Pebble.FeatureFlags.TargetSet
  alias Elmc.Backend.Pebble.Types

  @spec compute(Types.call_target_set()) :: Types.draw_primitive_flags()
  def compute(targets) do
    %{
      draw_clear: TargetSet.member?(targets, "Pebble.Ui.clear"),
      draw_pixel: TargetSet.member?(targets, "Pebble.Ui.pixel"),
      draw_line: TargetSet.member?(targets, "Pebble.Ui.line"),
      draw_rect: TargetSet.member?(targets, "Pebble.Ui.rect"),
      draw_fill_rect: TargetSet.member?(targets, "Pebble.Ui.fillRect"),
      draw_circle: TargetSet.member?(targets, "Pebble.Ui.circle"),
      draw_fill_circle: TargetSet.member?(targets, "Pebble.Ui.fillCircle"),
      draw_round_rect: TargetSet.member?(targets, "Pebble.Ui.roundRect"),
      draw_arc: TargetSet.member?(targets, "Pebble.Ui.arc"),
      draw_path:
        TargetSet.member?(targets, "Pebble.Ui.pathFilled") or
          TargetSet.member?(targets, "Pebble.Ui.pathOutline") or
          TargetSet.member?(targets, "Pebble.Ui.pathOutlineOpen"),
      draw_fill_radial: TargetSet.member?(targets, "Pebble.Ui.fillRadial"),
      draw_bitmap_in_rect: TargetSet.member?(targets, "Pebble.Ui.drawBitmapInRect"),
      draw_vector_at: TargetSet.member?(targets, "Pebble.Ui.drawVectorAt"),
      draw_vector_sequence_at: TargetSet.member?(targets, "Pebble.Ui.drawVectorSequenceAt"),
      draw_bitmap_sequence_at: TargetSet.member?(targets, "Pebble.Ui.drawBitmapSequenceAt"),
      draw_rotated_bitmap: TargetSet.member?(targets, "Pebble.Ui.drawRotatedBitmap")
    }
  end
end
