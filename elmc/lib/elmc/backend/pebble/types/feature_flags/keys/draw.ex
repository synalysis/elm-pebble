defmodule Elmc.Backend.Pebble.Types.FeatureFlags.Keys.Draw do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @primitive_keys [
    :draw_clear,
    :draw_pixel,
    :draw_line,
    :draw_rect,
    :draw_fill_rect,
    :draw_circle,
    :draw_fill_circle,
    :draw_round_rect,
    :draw_arc,
    :draw_path,
    :draw_fill_radial,
    :draw_bitmap_in_rect,
    :draw_vector_at,
    :draw_vector_sequence_at,
    :draw_bitmap_sequence_at,
    :draw_rotated_bitmap
  ]

  @context_keys [
    :draw_context,
    :draw_stroke_width,
    :draw_antialiased,
    :draw_stroke_color,
    :draw_fill_color,
    :draw_text_color,
    :draw_compositing_mode
  ]

  @text_keys [:draw_text_int, :draw_text_label, :draw_text, :draw_text_any]

  @keys [
    :draw_text_int,
    :draw_clear,
    :draw_pixel,
    :draw_line,
    :draw_rect,
    :draw_fill_rect,
    :draw_circle,
    :draw_fill_circle,
    :draw_text_label,
    :draw_context,
    :draw_stroke_width,
    :draw_antialiased,
    :draw_stroke_color,
    :draw_fill_color,
    :draw_text_color,
    :draw_round_rect,
    :draw_arc,
    :draw_path,
    :draw_fill_radial,
    :draw_compositing_mode,
    :draw_bitmap_in_rect,
    :draw_vector_at,
    :draw_vector_sequence_at,
    :draw_bitmap_sequence_at,
    :draw_rotated_bitmap,
    :draw_text,
    :draw_text_any
  ]

  @spec keys() :: [Types.feature_flag_key()]
  def keys, do: @keys

  @spec primitive_keys() :: [Types.feature_flag_key()]
  def primitive_keys, do: @primitive_keys

  @spec context_keys() :: [Types.feature_flag_key()]
  def context_keys, do: @context_keys

  @spec text_keys() :: [Types.feature_flag_key()]
  def text_keys, do: @text_keys
end
