defmodule Elmc.Backend.CCodegen.SpecialValues.Draw do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Constants
  alias Elmc.Backend.CCodegen.Emit
  alias Elmc.Backend.CCodegen.SpecialValues.{Core, Helpers}
  alias Elmc.Backend.CCodegen.Types

  @behaviour Elmc.Backend.CCodegen.SpecialValues.Handler

  @impl true
  @spec special_value_from_target(String.t(), Types.special_value_args()) ::
          Types.special_value_result()


  def special_value_from_target("Pebble.Ui.clear", args),
    do: Helpers.encoded_draw_cmd_expr(Helpers.draw_kind(:clear), args, 1)

  def special_value_from_target("Pebble.Ui.pixel", [pos, color]),
    do:
      Helpers.encoded_draw_field_cmd_expr(
        Helpers.draw_kind(:pixel),
        [Helpers.field_access_expr(pos, "x"), Helpers.field_access_expr(pos, "y"), color],
        3
      )

  def special_value_from_target("Pebble.Ui.pixel", args),
    do: Helpers.encoded_draw_cmd_expr(Helpers.draw_kind(:pixel), args, 3)

  def special_value_from_target("Pebble.Ui.line", [start_pos, end_pos, color]),
    do:
      Helpers.encoded_draw_field_cmd_expr(
        Helpers.draw_kind(:line),
        [
          Helpers.field_access_expr(start_pos, "x"),
          Helpers.field_access_expr(start_pos, "y"),
          Helpers.field_access_expr(end_pos, "x"),
          Helpers.field_access_expr(end_pos, "y"),
          color
        ],
        5
      )

  def special_value_from_target("Pebble.Ui.line", args),
    do: Helpers.encoded_draw_cmd_expr(Helpers.draw_kind(:line), args, 5)

  def special_value_from_target("Pebble.Ui.rect", [bounds, color]),
    do:
      Helpers.encoded_draw_field_cmd_expr(
        Helpers.draw_kind(:rect),
        [
          Helpers.field_access_expr(bounds, "x"),
          Helpers.field_access_expr(bounds, "y"),
          Helpers.field_access_expr(bounds, "w"),
          Helpers.field_access_expr(bounds, "h"),
          color
        ],
        5
      )

  def special_value_from_target("Pebble.Ui.rect", args),
    do: Helpers.encoded_draw_cmd_expr(Helpers.draw_kind(:rect), args, 5)

  def special_value_from_target("Pebble.Ui.fillRect", [bounds, color]),
    do:
      Helpers.encoded_draw_field_cmd_expr(
        Helpers.draw_kind(:fill_rect),
        [
          Helpers.field_access_expr(bounds, "x"),
          Helpers.field_access_expr(bounds, "y"),
          Helpers.field_access_expr(bounds, "w"),
          Helpers.field_access_expr(bounds, "h"),
          color
        ],
        5
      )

  def special_value_from_target("Pebble.Ui.fillRect", args),
    do: Helpers.encoded_draw_cmd_expr(Helpers.draw_kind(:fill_rect), args, 5)

  def special_value_from_target("Pebble.Ui.circle", [center, radius, color]),
    do:
      Helpers.encoded_draw_field_cmd_expr(
        Helpers.draw_kind(:circle),
        [Helpers.field_access_expr(center, "x"), Helpers.field_access_expr(center, "y"), radius, color],
        4
      )

  def special_value_from_target("Pebble.Ui.circle", args),
    do: Helpers.encoded_draw_cmd_expr(Helpers.draw_kind(:circle), args, 4)

  def special_value_from_target("Pebble.Ui.fillCircle", [center, radius, color]),
    do:
      Helpers.encoded_draw_field_cmd_expr(
        Helpers.draw_kind(:fill_circle),
        [Helpers.field_access_expr(center, "x"), Helpers.field_access_expr(center, "y"), radius, color],
        4
      )

  def special_value_from_target("Pebble.Ui.fillCircle", args),
    do: Helpers.encoded_draw_cmd_expr(Helpers.draw_kind(:fill_circle), args, 4)

  def special_value_from_target("Pebble.Ui.textInt", [font_id, pos, value]),
    do:
      Helpers.encoded_draw_field_cmd_expr(
        Helpers.draw_kind(:text_int_with_font),
        [font_id, Helpers.field_access_expr(pos, "x"), Helpers.field_access_expr(pos, "y"), value],
        4
      )

  def special_value_from_target("Pebble.Ui.textLabel", [font_id, pos, label]),
    do:
      Helpers.encoded_text_cmd_expr(
        Helpers.draw_kind(:text_label_with_font),
        [
          font_id,
          Helpers.field_access_expr(pos, "x"),
          Helpers.field_access_expr(pos, "y"),
          %{op: :int_literal, value: 0},
          %{op: :int_literal, value: 0},
          label
        ]
      )

  def special_value_from_target("Pebble.Ui.text", [font_id, options, bounds, value]),
    do:
      Helpers.encoded_text_cmd_expr(
        Helpers.draw_kind(:text),
        [
          font_id,
          Helpers.field_access_expr(bounds, "x"),
          Helpers.field_access_expr(bounds, "y"),
          Helpers.field_access_expr(bounds, "w"),
          Helpers.field_access_expr(bounds, "h"),
          Helpers.text_options_special_arg(options),
          value
        ]
      )

  def special_value_from_target("Pebble.Ui.defaultTextOptions", []),
    do: %{
      op: :record_literal,
      fields: [
        %{name: "alignment", expr: Helpers.text_alignment_expr(:center)},
        %{name: "overflow", expr: Helpers.text_overflow_expr(:word_wrap)}
      ]
    }

  def special_value_from_target("Pebble.Ui.alignLeft", [options]),
    do: Helpers.text_options_update_expr(options, "alignment", Helpers.text_alignment_expr(:left))

  def special_value_from_target("Pebble.Ui.alignCenter", [options]),
    do: Helpers.text_options_update_expr(options, "alignment", Helpers.text_alignment_expr(:center))

  def special_value_from_target("Pebble.Ui.alignRight", [options]),
    do: Helpers.text_options_update_expr(options, "alignment", Helpers.text_alignment_expr(:right))

  def special_value_from_target("Pebble.Ui.wordWrap", [options]),
    do: Helpers.text_options_update_expr(options, "overflow", Helpers.text_overflow_expr(:word_wrap))

  def special_value_from_target("Pebble.Ui.trailingEllipsis", [options]),
    do: Helpers.text_options_update_expr(options, "overflow", Helpers.text_overflow_expr(:trailing_ellipsis))

  def special_value_from_target("Pebble.Ui.fillOverflow", [options]),
    do: Helpers.text_options_update_expr(options, "overflow", Helpers.text_overflow_expr(:fill))

  def special_value_from_target("Pebble.Ui.AlignLeft", []), do: Helpers.text_alignment_expr(:left)
  def special_value_from_target("Pebble.Ui.AlignCenter", []), do: Helpers.text_alignment_expr(:center)
  def special_value_from_target("Pebble.Ui.AlignRight", []), do: Helpers.text_alignment_expr(:right)
  def special_value_from_target("Pebble.Ui.WordWrap", []), do: Helpers.text_overflow_expr(:word_wrap)

  def special_value_from_target("Pebble.Ui.TrailingEllipsis", []),
    do: Helpers.text_overflow_expr(:trailing_ellipsis)

  def special_value_from_target("Pebble.Ui.Fill", []), do: Helpers.text_overflow_expr(:fill)

  def special_value_from_target("Pebble.Ui.Color.indexed", [value]), do: value

  def special_value_from_target("Pebble.Ui.Color.toInt", [value]), do: value

  def special_value_from_target("Pebble.Ui.rotationFromPebbleAngle", [angle]),
    do: Helpers.rotation_expr(angle)

  def special_value_from_target("Pebble.Ui.rotationToPebbleAngle", [rotation]) do
    case Helpers.compile_time_pebble_angle_expr(rotation) do
      {:ok, expr} -> expr
      :error -> nil
    end
  end

  def special_value_from_target("Pebble.Ui.rotationFromDegrees", [
        %{op: :int_literal, value: degrees}
      ]),
      do: Helpers.rotation_expr(%{op: :int_literal, value: Helpers.pebble_angle_from_degrees(degrees)})

  def special_value_from_target("Pebble.Ui.rotationFromDegrees", [
        %{op: :float_literal, value: degrees}
      ]),
      do: Helpers.rotation_expr(%{op: :int_literal, value: Helpers.pebble_angle_from_degrees(degrees)})

  def special_value_from_target("Pebble.Ui.Color." <> name, []) do
    case Map.fetch(Constants.pebble_color_constants(), name) do
      {:ok, _value} -> %{op: :c_int_expr, value: Emit.generated_color_macro(name)}
      :error -> nil
    end
  end

  def special_value_from_target("Pebble.Time.Monday", []), do: %{op: :int_literal, value: 0}
  def special_value_from_target("Pebble.Time.Tuesday", []), do: %{op: :int_literal, value: 1}
  def special_value_from_target("Pebble.Time.Wednesday", []), do: %{op: :int_literal, value: 2}
  def special_value_from_target("Pebble.Time.Thursday", []), do: %{op: :int_literal, value: 3}
  def special_value_from_target("Pebble.Time.Friday", []), do: %{op: :int_literal, value: 4}
  def special_value_from_target("Pebble.Time.Saturday", []), do: %{op: :int_literal, value: 5}
  def special_value_from_target("Pebble.Time.Sunday", []), do: %{op: :int_literal, value: 6}

  def special_value_from_target("PushContext", args),
    do: Helpers.encoded_draw_cmd_expr(Helpers.draw_kind(:push_context), args, 0)

  def special_value_from_target("PopContext", args),
    do: Helpers.encoded_draw_cmd_expr(Helpers.draw_kind(:pop_context), args, 0)

  def special_value_from_target("Pebble.Ui.strokeWidth", [value]),
    do: Helpers.tagged_value_expr(Helpers.context_kind_expr(:stroke_width), value)

  def special_value_from_target("Pebble.Ui.antialiased", [value]),
    do: Helpers.tagged_value_expr(Helpers.context_kind_expr(:antialiased), value)

  def special_value_from_target("Pebble.Ui.strokeColor", [value]),
    do: Helpers.tagged_value_expr(Helpers.context_kind_expr(:stroke_color), value)

  def special_value_from_target("Pebble.Ui.fillColor", [value]),
    do: Helpers.tagged_value_expr(Helpers.context_kind_expr(:fill_color), value)

  def special_value_from_target("Pebble.Ui.textColor", [value]),
    do: Helpers.tagged_value_expr(Helpers.context_kind_expr(:text_color), value)

  def special_value_from_target("Pebble.Ui.compositingMode", [value]),
    do: Helpers.tagged_value_expr(Helpers.context_kind_expr(:compositing_mode), value)

  def special_value_from_target("Pebble.Ui.context", [settings, commands]),
    do: %{op: :tuple2, left: settings, right: commands}

  def special_value_from_target("Pebble.Ui.group", [context]),
    do: %{
      op: :tuple2,
      left: Helpers.draw_kind_expr(:context_group),
      right: context
    }

  def special_value_from_target("Pebble.Ui.path", [points, offset_x, offset_y, rotation]),
    do: Helpers.path_expr(points, offset_x, offset_y, rotation)

  def special_value_from_target("Pebble.Ui.pathFilled", [path]),
    do: %{op: :tuple2, left: Helpers.draw_kind_expr(:path_filled), right: path}

  def special_value_from_target("Pebble.Ui.pathOutline", [path]),
    do: %{op: :tuple2, left: Helpers.draw_kind_expr(:path_outline), right: path}

  def special_value_from_target("Pebble.Ui.pathOutlineOpen", [path]),
    do: %{
      op: :tuple2,
      left: Helpers.draw_kind_expr(:path_outline_open),
      right: path
    }

  def special_value_from_target("Pebble.Ui.roundRect", [bounds, radius, color]),
    do:
      Helpers.encoded_draw_field_cmd_expr(
        Helpers.draw_kind(:round_rect),
        [
          Helpers.field_access_expr(bounds, "x"),
          Helpers.field_access_expr(bounds, "y"),
          Helpers.field_access_expr(bounds, "w"),
          Helpers.field_access_expr(bounds, "h"),
          radius,
          color
        ],
        6
      )

  def special_value_from_target("Pebble.Ui.roundRect", args),
    do: Helpers.encoded_draw_cmd_expr(Helpers.draw_kind(:round_rect), args, 6)

  def special_value_from_target("Pebble.Ui.arc", [bounds, start_angle, end_angle]),
    do:
      Helpers.encoded_draw_field_cmd_expr(
        Helpers.draw_kind(:arc),
        [
          Helpers.field_access_expr(bounds, "x"),
          Helpers.field_access_expr(bounds, "y"),
          Helpers.field_access_expr(bounds, "w"),
          Helpers.field_access_expr(bounds, "h"),
          start_angle,
          end_angle
        ],
        6
      )

  def special_value_from_target("Pebble.Ui.arc", args),
    do: Helpers.encoded_draw_cmd_expr(Helpers.draw_kind(:arc), args, 6)

  def special_value_from_target("Pebble.Ui.fillRadial", [bounds, start_angle, end_angle]),
    do:
      Helpers.encoded_draw_field_cmd_expr(
        Helpers.draw_kind(:fill_radial),
        [
          Helpers.field_access_expr(bounds, "x"),
          Helpers.field_access_expr(bounds, "y"),
          Helpers.field_access_expr(bounds, "w"),
          Helpers.field_access_expr(bounds, "h"),
          start_angle,
          end_angle
        ],
        6
      )

  def special_value_from_target("Pebble.Ui.fillRadial", args),
    do: Helpers.encoded_draw_cmd_expr(Helpers.draw_kind(:fill_radial), args, 6)

  def special_value_from_target("Pebble.Ui.drawBitmapInRect", [bitmap, bounds]),
    do:
      Helpers.encoded_draw_field_cmd_expr(
        Helpers.draw_kind(:bitmap_in_rect),
        [
          bitmap,
          Helpers.field_access_expr(bounds, "x"),
          Helpers.field_access_expr(bounds, "y"),
          Helpers.field_access_expr(bounds, "w"),
          Helpers.field_access_expr(bounds, "h")
        ],
        5
      )

  def special_value_from_target("Pebble.Ui.drawVectorAt", [vector, origin]),
    do:
      Helpers.encoded_draw_field_cmd_expr(
        Helpers.draw_kind(:vector_at),
        [
          vector,
          Helpers.field_access_expr(origin, "x"),
          Helpers.field_access_expr(origin, "y")
        ],
        3
      )

  def special_value_from_target("Pebble.Ui.drawVectorSequenceAt", [anim_id, vector, origin]),
    do:
      Helpers.encoded_draw_field_cmd_expr(
        Helpers.draw_kind(:vector_sequence_at),
        [
          Helpers.animation_id_int_expr(anim_id),
          vector,
          Helpers.field_access_expr(origin, "x"),
          Helpers.field_access_expr(origin, "y")
        ],
        4
      )

  def special_value_from_target("Pebble.Ui.drawBitmapSequenceAt", [anim_id, animation, origin]),
    do:
      Helpers.encoded_draw_field_cmd_expr(
        Helpers.draw_kind(:bitmap_sequence_at),
        [
          Helpers.animation_id_int_expr(anim_id),
          animation,
          Helpers.field_access_expr(origin, "x"),
          Helpers.field_access_expr(origin, "y")
        ],
        4
      )

  def special_value_from_target("Pebble.Ui.drawBitmapInRect", args),
    do: Helpers.encoded_draw_cmd_expr(Helpers.draw_kind(:bitmap_in_rect), args, 5)

  def special_value_from_target("Pebble.Ui.drawRotatedBitmap", [bitmap, bounds, rotation, center]),
      do:
        Helpers.encoded_draw_field_cmd_expr(
          Helpers.draw_kind(:rotated_bitmap),
          [
            bitmap,
            Helpers.field_access_expr(bounds, "w"),
            Helpers.field_access_expr(bounds, "h"),
            Core.pebble_angle_expr(rotation),
            Helpers.field_access_expr(center, "x"),
            Helpers.field_access_expr(center, "y")
          ],
          6
        )

  def special_value_from_target("Pebble.Ui.drawRotatedBitmap", args),
    do: Helpers.encoded_draw_cmd_expr(Helpers.draw_kind(:rotated_bitmap), args, 6)

  def special_value_from_target("Pebble.Ui.windowStack", [windows]),
    do: %{
      op: :tuple2,
      left: Helpers.ui_node_kind_expr(:window_stack),
      right: windows
    }

  def special_value_from_target("Pebble.Ui.window", [window_id, layers]),
    do: %{
      op: :tuple2,
      left: Helpers.ui_node_kind_expr(:window_node),
      right: %{op: :tuple2, left: window_id, right: layers}
    }

  def special_value_from_target("Pebble.Ui.canvasLayer", [layer_id, ops]),
    do: %{
      op: :tuple2,
      left: Helpers.ui_node_kind_expr(:canvas_layer),
      right: %{op: :tuple2, left: layer_id, right: ops}
    }


  def special_value_from_target(_target, _args), do: nil
end
