defmodule Elmc.Backend.Pebble.FeatureFlags.DrawFlags.Compact do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @legacy_required_keys ~w(
    draw_context
    draw_clear
    draw_rect
    draw_text
    draw_stroke_color
    draw_text_color
  )a

  @legacy_forbidden_keys ~w(
    draw_text_int
    draw_text_label
    draw_pixel
    draw_line
    draw_fill_rect
    draw_circle
    draw_fill_circle
    draw_round_rect
    draw_arc
    draw_path
    draw_fill_radial
    draw_bitmap_in_rect
    draw_vector_at
    draw_vector_sequence_at
    draw_bitmap_sequence_at
    draw_rotated_bitmap
    draw_stroke_width
    draw_antialiased
    draw_fill_color
    draw_compositing_mode
  )a

  @minimal_required_keys ~w(
    draw_clear
    draw_fill_rect
  )a

  @minimal_forbidden_keys ~w(
    draw_text_int
    draw_text_label
    draw_pixel
    draw_line
    draw_rect
    draw_circle
    draw_fill_circle
    draw_text
    draw_context
    draw_stroke_width
    draw_antialiased
    draw_stroke_color
    draw_fill_color
    draw_text_color
    draw_round_rect
    draw_arc
    draw_path
    draw_fill_radial
    draw_compositing_mode
    draw_bitmap_in_rect
    draw_vector_at
    draw_vector_sequence_at
    draw_bitmap_sequence_at
    draw_rotated_bitmap
  )a

  @spec compute(Types.draw_feature_flags()) :: %{compact_draw: boolean()}
  def compute(%{} = flags) do
    legacy_compact? =
      Enum.all?(@legacy_required_keys, &Map.fetch!(flags, &1)) and
        Enum.all?(@legacy_forbidden_keys, &(not Map.fetch!(flags, &1)))

    minimal_compact? =
      Enum.all?(@minimal_required_keys, &Map.fetch!(flags, &1)) and
        Enum.all?(@minimal_forbidden_keys, &(not Map.fetch!(flags, &1)))

    %{compact_draw: legacy_compact? or minimal_compact?}
  end
end
