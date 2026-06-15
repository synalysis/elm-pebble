defmodule Elmx.Runtime.Pebble.Registry.Ui do
  @moduledoc false

  alias Elmx.Runtime.Handler
  alias Elmx.Runtime.Pebble.Dispatch
  alias Elmx.Runtime.Pebble.Ui

  @type handler :: Handler.t()

  @spec handlers() :: %{String.t() => handler()}
  def handlers do
    base =
      for fun <- ~w(
             to_ui_node window_stack window canvas_layer group context draw_bitmap_in_rect clear
             fill_rect text text_int text_label rect circle fill_circle fill_radial pixel round_rect
             arc path path_outline path_filled path_outline_open rotation_from_degrees
             draw_vector_at draw_vector_sequence_at draw_bitmap_sequence_at draw_rotated_bitmap
             compositing_mode named_color
           )a,
           into: %{} do
        {"elmx_ui_#{fun}", {Ui, fun}}
      end

    ctx =
      for key <- ~w(
             stroke_width antialiased stroke_color fill_color text_color align_left align_center
             align_right word_wrap trailing_ellipsis fill_overflow
           ) do
        {"elmx_ui_#{key}", {Dispatch, :ui_context_setting, key: key}}
      end

    Map.merge(base, Map.new(ctx))
    |> Map.put("elmx_ui_line", {Dispatch, :ui_line})
    |> Map.put("elmx_ui_rotation_from_pebble_angle", {Dispatch, :rotation_from_pebble_angle})
  end
end
