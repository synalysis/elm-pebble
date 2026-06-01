defmodule Elmx.Runtime.Pebble.SpecialValues.Ui do
  @moduledoc false

  import Elmx.Runtime.Pebble.SpecialValues.Helpers

  alias Elmx.Types

  @spec rewrite(String.t(), Types.ir_arg_list()) :: Types.dispatch_result()
  def rewrite(target, args) when is_binary(target) and is_list(args) do
    case target do
      "Pebble.Ui.drawBitmapInRect" -> ui_call("elmx_ui_draw_bitmap_in_rect", args)
      "Pebble.Ui.clear" -> ui_call("elmx_ui_clear", args)
      "Pebble.Ui.fillRect" -> ui_call("elmx_ui_fill_rect", args)
      "Pebble.Ui.text" -> ui_call("elmx_ui_text", args)
      "Pebble.Ui.textInt" -> ui_call("elmx_ui_text_int", args)
      "Pebble.Ui.textLabel" -> ui_call("elmx_ui_text_label", args)
      "Pebble.Ui.rect" -> ui_call("elmx_ui_rect", args)
      "Pebble.Ui.line" -> ui_call("elmx_ui_line", args)
      "Pebble.Ui.circle" -> ui_call("elmx_ui_circle", args)
      "Pebble.Ui.fillCircle" -> ui_call("elmx_ui_fill_circle", args)
      "Pebble.Ui.fillRadial" -> ui_call("elmx_ui_fill_radial", args)
      "Pebble.Ui.pixel" -> ui_call("elmx_ui_pixel", args)
      "Pebble.Ui.strokeWidth" -> ui_call("elmx_ui_stroke_width", args)
      "Pebble.Ui.antialiased" -> ui_call("elmx_ui_antialiased", args)
      "Pebble.Ui.strokeColor" -> ui_call("elmx_ui_stroke_color", args)
      "Pebble.Ui.fillColor" -> ui_call("elmx_ui_fill_color", args)
      "Pebble.Ui.textColor" -> ui_call("elmx_ui_text_color", args)
      "Pebble.Ui.defaultTextOptions" -> {:ok, %{op: :list_literal, items: []}}
      "Pebble.Ui.context" -> ui_call("elmx_ui_context", args)
      "Pebble.Ui.group" -> ui_call("elmx_ui_group", args)
      "Pebble.Ui.alignLeft" -> ui_call("elmx_ui_align_left", args)
      "Pebble.Ui.AlignLeft" -> ui_call("elmx_ui_align_left", args)
      "Pebble.Ui.alignCenter" -> ui_call("elmx_ui_align_center", args)
      "Pebble.Ui.AlignCenter" -> ui_call("elmx_ui_align_center", args)
      "Pebble.Ui.alignRight" -> ui_call("elmx_ui_align_right", args)
      "Pebble.Ui.AlignRight" -> ui_call("elmx_ui_align_right", args)
      "Pebble.Ui.wordWrap" -> ui_call("elmx_ui_word_wrap", args)
      "Pebble.Ui.WordWrap" -> ui_call("elmx_ui_word_wrap", args)
      "Pebble.Ui.trailingEllipsis" -> ui_call("elmx_ui_trailing_ellipsis", args)
      "Pebble.Ui.TrailingEllipsis" -> ui_call("elmx_ui_trailing_ellipsis", args)
      "Pebble.Ui.fillOverflow" -> ui_call("elmx_ui_fill_overflow", args)
      "Pebble.Ui.Fill" -> ui_call("elmx_ui_fill_overflow", args)
      "Pebble.Ui.drawVectorAt" -> ui_call("elmx_ui_draw_vector_at", args)
      "Pebble.Ui.drawVectorSequenceAt" -> ui_call("elmx_ui_draw_vector_sequence_at", args)
      "Pebble.Ui.drawBitmapSequenceAt" -> ui_call("elmx_ui_draw_bitmap_sequence_at", args)
      "Pebble.Ui.drawRotatedBitmap" -> ui_call("elmx_ui_draw_rotated_bitmap", args)
      "Pebble.Ui.compositingMode" -> ui_call("elmx_ui_compositing_mode", args)
      "Pebble.Ui.rotationFromDegrees" -> ui_call("elmx_ui_rotation_from_degrees", args)
      "Pebble.Ui.roundRect" -> ui_call("elmx_ui_round_rect", args)
      "Pebble.Ui.arc" -> ui_call("elmx_ui_arc", args)
      "Pebble.Ui.path" -> ui_call("elmx_ui_path", args)
      "Pebble.Ui.pathOutline" -> ui_call("elmx_ui_path_outline", args)
      "Pebble.Ui.pathFilled" -> ui_call("elmx_ui_path_filled", args)
      "Pebble.Ui.pathOutlineOpen" -> ui_call("elmx_ui_path_outline_open", args)
      "Pebble.Ui.rotationFromPebbleAngle" -> ui_call("elmx_ui_rotation_from_pebble_angle", args)
      "Pebble.Ui.windowStack" -> ui_call("elmx_ui_window_stack", args)
      "Pebble.Ui.window" -> ui_call("elmx_ui_window", args)
      "Pebble.Ui.canvasLayer" -> ui_call("elmx_ui_canvas_layer", args)
      "Pebble.Ui.Color.indexed" -> passthrough_arg(args)
      "Pebble.Ui.Color.toInt" -> passthrough_arg(args)
      "Pebble.Ui.Color." <> color_name ->
        {:ok,
         %{
           op: :runtime_call,
           function: "elmx_ui_named_color",
           args: [%{op: :string_literal, value: color_name}]
         }}

      "Pebble.Ui.Resources." <> resource_name ->
        {:ok, %{op: :string_literal, value: resource_name}}

      _ ->
        :unmatched
    end
  end
end
