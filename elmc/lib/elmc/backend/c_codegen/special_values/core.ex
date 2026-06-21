defmodule Elmc.Backend.CCodegen.SpecialValues.Core do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Constants
  alias Elmc.Backend.CCodegen.PebbleMsgTag
  alias Elmc.Backend.CCodegen.Subscriptions
  alias Elmc.Backend.CCodegen.Emit
  alias Elmc.Backend.CCodegen.IRQueries
  alias Elmc.Backend.CCodegen.Types

  @spec draw_kind(Elmc.Backend.Pebble.Kinds.draw_kind()) :: non_neg_integer()
  defp draw_kind(kind), do: Elmc.Backend.Pebble.draw_kind_id!(kind)

  defp command_kind(kind), do: Elmc.Backend.Pebble.command_kind_id!(kind)

  defp command_kind_expr(kind),
    do: %{op: :c_int_expr, value: Elmc.Backend.Pebble.command_kind_c_name!(kind)}

  defp encoded_to_msg_cmd(kind, to_msg),
    do: encoded_cmd_expr(command_kind(kind), [constructor_tag_expr(to_msg)], 1)

  defp ui_node_kind_expr(kind), do: %{op: :c_int_expr, value: generated_ui_node_kind_macro(kind)}
  defp context_kind_expr(kind), do: %{op: :c_int_expr, value: generated_context_kind_macro(kind)}

  defp draw_kind_expr(kind), do: %{op: :c_int_expr, value: generated_draw_kind_macro(kind)}

  def generated_draw_kind_macro(kind) when is_atom(kind) do
    kind
    |> Atom.to_string()
    |> String.upcase()
    |> then(&"ELMC_RENDER_OP_#{&1}")
  end

  def generated_draw_kind_macro(kind) when is_integer(kind) do
    kind
    |> Elmc.Backend.Pebble.draw_kind_c_name!()
    |> String.replace_prefix("ELMC_PEBBLE_DRAW_", "ELMC_RENDER_OP_")
  end

  defp generated_ui_node_kind_macro(:window_stack), do: "ELMC_UI_NODE_WINDOW_STACK"
  defp generated_ui_node_kind_macro(:window_node), do: "ELMC_UI_NODE_WINDOW"
  defp generated_ui_node_kind_macro(:canvas_layer), do: "ELMC_UI_NODE_CANVAS_LAYER"

  defp generated_context_kind_macro(:stroke_width), do: "ELMC_CONTEXT_STROKE_WIDTH"
  defp generated_context_kind_macro(:antialiased), do: "ELMC_CONTEXT_ANTIALIASED"
  defp generated_context_kind_macro(:stroke_color), do: "ELMC_CONTEXT_STROKE_COLOR"
  defp generated_context_kind_macro(:fill_color), do: "ELMC_CONTEXT_FILL_COLOR"
  defp generated_context_kind_macro(:text_color), do: "ELMC_CONTEXT_TEXT_COLOR"
  defp generated_context_kind_macro(:compositing_mode), do: "ELMC_CONTEXT_COMPOSITING_MODE"

  defp text_options_special_arg(%{op: :var} = options), do: options

  defp text_options_special_arg(options),
    do: Elmc.Backend.CCodegen.Host.text_options_expr(options)

  defp subscription_special_value(target, args) do
    case Subscriptions.subscription_sub_expr(target, args) do
      nil -> %{op: :unsupported}
      expr -> expr
    end
  end

  @spec msg_tag_param(Types.ir_expr()) :: Types.ir_expr()
  def msg_tag_param(expr), do: constructor_tag_expr(expr)

  @spec subscription_to_msg_params([Types.ir_expr()]) :: [Types.ir_expr()]
  def subscription_to_msg_params(args) when is_list(args) do
    case List.last(args) do
      nil -> []
      to_msg -> [constructor_tag_expr(to_msg)]
    end
  end

  @spec encoded_sub_as_tuple(map(), [map()]) :: map()
  def encoded_sub_as_tuple(mask_expr, args) when is_list(args) do
    arity = length(args)
    payload = args ++ List.duplicate(%{op: :int_literal, value: 0}, max(0, 6 - arity))
    %{op: :tuple2, left: mask_expr, right: tuple_chain(payload)}
  end

  @spec special_value_from_target(String.t(), [Types.ir_expr()]) :: Types.ir_expr() | nil
  def special_value_from_target("Pebble.Ui.clear", args),
    do: encoded_draw_cmd_expr(draw_kind(:clear), args, 1)

  def special_value_from_target("Pebble.Ui.pixel", [pos, color]),
    do:
      encoded_draw_field_cmd_expr(
        draw_kind(:pixel),
        [field_access_expr(pos, "x"), field_access_expr(pos, "y"), color],
        3
      )

  def special_value_from_target("Pebble.Ui.pixel", args),
    do: encoded_draw_cmd_expr(draw_kind(:pixel), args, 3)

  def special_value_from_target("Pebble.Ui.line", [start_pos, end_pos, color]),
    do:
      encoded_draw_field_cmd_expr(
        draw_kind(:line),
        [
          field_access_expr(start_pos, "x"),
          field_access_expr(start_pos, "y"),
          field_access_expr(end_pos, "x"),
          field_access_expr(end_pos, "y"),
          color
        ],
        5
      )

  def special_value_from_target("Pebble.Ui.line", args),
    do: encoded_draw_cmd_expr(draw_kind(:line), args, 5)

  def special_value_from_target("Pebble.Ui.rect", [bounds, color]),
    do:
      encoded_draw_field_cmd_expr(
        draw_kind(:rect),
        [
          field_access_expr(bounds, "x"),
          field_access_expr(bounds, "y"),
          field_access_expr(bounds, "w"),
          field_access_expr(bounds, "h"),
          color
        ],
        5
      )

  def special_value_from_target("Pebble.Ui.rect", args),
    do: encoded_draw_cmd_expr(draw_kind(:rect), args, 5)

  def special_value_from_target("Pebble.Ui.fillRect", [bounds, color]),
    do:
      encoded_draw_field_cmd_expr(
        draw_kind(:fill_rect),
        [
          field_access_expr(bounds, "x"),
          field_access_expr(bounds, "y"),
          field_access_expr(bounds, "w"),
          field_access_expr(bounds, "h"),
          color
        ],
        5
      )

  def special_value_from_target("Pebble.Ui.fillRect", args),
    do: encoded_draw_cmd_expr(draw_kind(:fill_rect), args, 5)

  def special_value_from_target("Pebble.Ui.circle", [center, radius, color]),
    do:
      encoded_draw_field_cmd_expr(
        draw_kind(:circle),
        [field_access_expr(center, "x"), field_access_expr(center, "y"), radius, color],
        4
      )

  def special_value_from_target("Pebble.Ui.circle", args),
    do: encoded_draw_cmd_expr(draw_kind(:circle), args, 4)

  def special_value_from_target("Pebble.Ui.fillCircle", [center, radius, color]),
    do:
      encoded_draw_field_cmd_expr(
        draw_kind(:fill_circle),
        [field_access_expr(center, "x"), field_access_expr(center, "y"), radius, color],
        4
      )

  def special_value_from_target("Pebble.Ui.fillCircle", args),
    do: encoded_draw_cmd_expr(draw_kind(:fill_circle), args, 4)

  def special_value_from_target("Pebble.Ui.textInt", [font_id, pos, value]),
    do:
      encoded_draw_field_cmd_expr(
        draw_kind(:text_int_with_font),
        [font_id, field_access_expr(pos, "x"), field_access_expr(pos, "y"), value],
        4
      )

  def special_value_from_target("Pebble.Ui.textLabel", [font_id, pos, label]),
    do:
      encoded_text_cmd_expr(
        draw_kind(:text_label_with_font),
        [
          font_id,
          field_access_expr(pos, "x"),
          field_access_expr(pos, "y"),
          %{op: :int_literal, value: 0},
          %{op: :int_literal, value: 0},
          label
        ]
      )

  def special_value_from_target("Pebble.Ui.text", [font_id, options, bounds, value]),
    do:
      encoded_text_cmd_expr(
        draw_kind(:text),
        [
          font_id,
          field_access_expr(bounds, "x"),
          field_access_expr(bounds, "y"),
          field_access_expr(bounds, "w"),
          field_access_expr(bounds, "h"),
          text_options_special_arg(options),
          value
        ]
      )

  def special_value_from_target("Pebble.Ui.defaultTextOptions", []),
    do: %{
      op: :record_literal,
      fields: [
        %{name: "alignment", expr: text_alignment_expr(:center)},
        %{name: "overflow", expr: text_overflow_expr(:word_wrap)}
      ]
    }

  def special_value_from_target("Pebble.Ui.alignLeft", [options]),
    do: text_options_update_expr(options, "alignment", text_alignment_expr(:left))

  def special_value_from_target("Pebble.Ui.alignCenter", [options]),
    do: text_options_update_expr(options, "alignment", text_alignment_expr(:center))

  def special_value_from_target("Pebble.Ui.alignRight", [options]),
    do: text_options_update_expr(options, "alignment", text_alignment_expr(:right))

  def special_value_from_target("Pebble.Ui.wordWrap", [options]),
    do: text_options_update_expr(options, "overflow", text_overflow_expr(:word_wrap))

  def special_value_from_target("Pebble.Ui.trailingEllipsis", [options]),
    do: text_options_update_expr(options, "overflow", text_overflow_expr(:trailing_ellipsis))

  def special_value_from_target("Pebble.Ui.fillOverflow", [options]),
    do: text_options_update_expr(options, "overflow", text_overflow_expr(:fill))

  def special_value_from_target("Pebble.Ui.AlignLeft", []), do: text_alignment_expr(:left)
  def special_value_from_target("Pebble.Ui.AlignCenter", []), do: text_alignment_expr(:center)
  def special_value_from_target("Pebble.Ui.AlignRight", []), do: text_alignment_expr(:right)
  def special_value_from_target("Pebble.Ui.WordWrap", []), do: text_overflow_expr(:word_wrap)

  def special_value_from_target("Pebble.Ui.TrailingEllipsis", []),
    do: text_overflow_expr(:trailing_ellipsis)

  def special_value_from_target("Pebble.Ui.Fill", []), do: text_overflow_expr(:fill)

  def special_value_from_target("Pebble.Ui.Color.indexed", [value]), do: value

  def special_value_from_target("Pebble.Ui.Color.toInt", [value]), do: value

  def special_value_from_target("Pebble.Ui.rotationFromPebbleAngle", [angle]),
    do: rotation_expr(angle)

  def special_value_from_target("Pebble.Ui.rotationToPebbleAngle", [rotation]) do
    case compile_time_pebble_angle_expr(rotation) do
      {:ok, expr} -> expr
      :error -> nil
    end
  end

  def special_value_from_target("Pebble.Ui.rotationFromDegrees", [
        %{op: :int_literal, value: degrees}
      ]),
      do: rotation_expr(%{op: :int_literal, value: pebble_angle_from_degrees(degrees)})

  def special_value_from_target("Pebble.Ui.rotationFromDegrees", [
        %{op: :float_literal, value: degrees}
      ]),
      do: rotation_expr(%{op: :int_literal, value: pebble_angle_from_degrees(degrees)})

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
    do: encoded_draw_cmd_expr(draw_kind(:push_context), args, 0)

  def special_value_from_target("PopContext", args),
    do: encoded_draw_cmd_expr(draw_kind(:pop_context), args, 0)

  def special_value_from_target("Pebble.Ui.strokeWidth", [value]),
    do: tagged_value_expr(context_kind_expr(:stroke_width), value)

  def special_value_from_target("Pebble.Ui.antialiased", [value]),
    do: tagged_value_expr(context_kind_expr(:antialiased), value)

  def special_value_from_target("Pebble.Ui.strokeColor", [value]),
    do: tagged_value_expr(context_kind_expr(:stroke_color), value)

  def special_value_from_target("Pebble.Ui.fillColor", [value]),
    do: tagged_value_expr(context_kind_expr(:fill_color), value)

  def special_value_from_target("Pebble.Ui.textColor", [value]),
    do: tagged_value_expr(context_kind_expr(:text_color), value)

  def special_value_from_target("Pebble.Ui.compositingMode", [value]),
    do: tagged_value_expr(context_kind_expr(:compositing_mode), value)

  def special_value_from_target("Pebble.Ui.context", [settings, commands]),
    do: %{op: :tuple2, left: settings, right: commands}

  def special_value_from_target("Pebble.Ui.group", [context]),
    do: %{
      op: :tuple2,
      left: draw_kind_expr(:context_group),
      right: context
    }

  def special_value_from_target("Pebble.Ui.path", [points, offset_x, offset_y, rotation]),
    do: path_expr(points, offset_x, offset_y, rotation)

  def special_value_from_target("Pebble.Ui.pathFilled", [path]),
    do: %{op: :tuple2, left: draw_kind_expr(:path_filled), right: path}

  def special_value_from_target("Pebble.Ui.pathOutline", [path]),
    do: %{op: :tuple2, left: draw_kind_expr(:path_outline), right: path}

  def special_value_from_target("Pebble.Ui.pathOutlineOpen", [path]),
    do: %{
      op: :tuple2,
      left: draw_kind_expr(:path_outline_open),
      right: path
    }

  def special_value_from_target("Pebble.Ui.roundRect", [bounds, radius, color]),
    do:
      encoded_draw_field_cmd_expr(
        draw_kind(:round_rect),
        [
          field_access_expr(bounds, "x"),
          field_access_expr(bounds, "y"),
          field_access_expr(bounds, "w"),
          field_access_expr(bounds, "h"),
          radius,
          color
        ],
        6
      )

  def special_value_from_target("Pebble.Ui.roundRect", args),
    do: encoded_draw_cmd_expr(draw_kind(:round_rect), args, 6)

  def special_value_from_target("Pebble.Ui.arc", [bounds, start_angle, end_angle]),
    do:
      encoded_draw_field_cmd_expr(
        draw_kind(:arc),
        [
          field_access_expr(bounds, "x"),
          field_access_expr(bounds, "y"),
          field_access_expr(bounds, "w"),
          field_access_expr(bounds, "h"),
          start_angle,
          end_angle
        ],
        6
      )

  def special_value_from_target("Pebble.Ui.arc", args),
    do: encoded_draw_cmd_expr(draw_kind(:arc), args, 6)

  def special_value_from_target("Pebble.Ui.fillRadial", [bounds, start_angle, end_angle]),
    do:
      encoded_draw_field_cmd_expr(
        draw_kind(:fill_radial),
        [
          field_access_expr(bounds, "x"),
          field_access_expr(bounds, "y"),
          field_access_expr(bounds, "w"),
          field_access_expr(bounds, "h"),
          start_angle,
          end_angle
        ],
        6
      )

  def special_value_from_target("Pebble.Ui.fillRadial", args),
    do: encoded_draw_cmd_expr(draw_kind(:fill_radial), args, 6)

  def special_value_from_target("Pebble.Ui.drawBitmapInRect", [bitmap, bounds]),
    do:
      encoded_draw_field_cmd_expr(
        draw_kind(:bitmap_in_rect),
        [
          bitmap,
          field_access_expr(bounds, "x"),
          field_access_expr(bounds, "y"),
          field_access_expr(bounds, "w"),
          field_access_expr(bounds, "h")
        ],
        5
      )

  def special_value_from_target("Pebble.Ui.drawVectorAt", [vector, origin]),
    do:
      encoded_draw_field_cmd_expr(
        draw_kind(:vector_at),
        [
          vector,
          field_access_expr(origin, "x"),
          field_access_expr(origin, "y")
        ],
        3
      )

  def special_value_from_target("Pebble.Ui.drawVectorSequenceAt", [vector, origin]),
    do:
      encoded_draw_field_cmd_expr(
        draw_kind(:vector_sequence_at),
        [
          vector,
          field_access_expr(origin, "x"),
          field_access_expr(origin, "y")
        ],
        3
      )

  def special_value_from_target("Pebble.Ui.drawBitmapSequenceAt", [animation, origin]),
    do:
      encoded_draw_field_cmd_expr(
        draw_kind(:bitmap_sequence_at),
        [
          animation,
          field_access_expr(origin, "x"),
          field_access_expr(origin, "y")
        ],
        3
      )

  def special_value_from_target("Pebble.Ui.drawBitmapInRect", args),
    do: encoded_draw_cmd_expr(draw_kind(:bitmap_in_rect), args, 5)

  def special_value_from_target("Pebble.Ui.drawRotatedBitmap", [bitmap, bounds, rotation, center]),
      do:
        encoded_draw_field_cmd_expr(
          draw_kind(:rotated_bitmap),
          [
            bitmap,
            field_access_expr(bounds, "w"),
            field_access_expr(bounds, "h"),
            pebble_angle_expr(rotation),
            field_access_expr(center, "x"),
            field_access_expr(center, "y")
          ],
          6
        )

  def special_value_from_target("Pebble.Ui.drawRotatedBitmap", args),
    do: encoded_draw_cmd_expr(draw_kind(:rotated_bitmap), args, 6)

  def special_value_from_target("Pebble.Ui.windowStack", [windows]),
    do: %{
      op: :tuple2,
      left: ui_node_kind_expr(:window_stack),
      right: windows
    }

  def special_value_from_target("Pebble.Ui.window", [window_id, layers]),
    do: %{
      op: :tuple2,
      left: ui_node_kind_expr(:window_node),
      right: %{op: :tuple2, left: window_id, right: layers}
    }

  def special_value_from_target("Pebble.Ui.canvasLayer", [layer_id, ops]),
    do: %{
      op: :tuple2,
      left: ui_node_kind_expr(:canvas_layer),
      right: %{op: :tuple2, left: layer_id, right: ops}
    }

  def special_value_from_target("List.cons", []),
    do: %{
      op: :lambda,
      args: ["__head", "__tail"],
      body: %{
        op: :runtime_call,
        function: "elmc_list_cons",
        args: [%{op: :var, name: "__head"}, %{op: :var, name: "__tail"}]
      }
    }

  def special_value_from_target("List.cons", [head]),
    do: %{
      op: :lambda,
      args: ["__tail"],
      body: %{
        op: :runtime_call,
        function: "elmc_list_cons",
        args: [head, %{op: :var, name: "__tail"}]
      }
    }

  def special_value_from_target("List.cons", [head, tail]),
    do: %{op: :runtime_call, function: "elmc_list_cons", args: [head, tail]}

  def special_value_from_target("Pebble.Cmd.none", _args),
    do: command_kind_expr(:none)

  def special_value_from_target("Elm.Kernel.PebbleWatch.none", _args),
    do: command_kind_expr(:none)

  def special_value_from_target("Pebble.Cmd.timerAfter", args),
    do: encoded_cmd_expr(command_kind(:timer_after_ms), args, 1)

  def special_value_from_target("Elm.Kernel.PebbleWatch.timerAfter", args),
    do: encoded_cmd_expr(command_kind(:timer_after_ms), args, 1)

  def special_value_from_target("Pebble.Cmd.storageWriteInt", args),
    do: encoded_cmd_expr(command_kind(:storage_write_int), args, 2)

  def special_value_from_target("Pebble.Storage.writeInt", args),
    do: encoded_cmd_expr(command_kind(:storage_write_int), args, 2)

  def special_value_from_target("Elm.Kernel.PebbleWatch.storageWriteInt", args),
    do: encoded_cmd_expr(command_kind(:storage_write_int), args, 2)

  def special_value_from_target("Pebble.Cmd.storageReadInt", [key, to_msg]),
    do: encoded_cmd_expr(command_kind(:storage_read_int), [key, constructor_tag_expr(to_msg)], 2)

  def special_value_from_target("Pebble.Storage.readInt", [key, to_msg]),
    do: encoded_cmd_expr(command_kind(:storage_read_int), [key, constructor_tag_expr(to_msg)], 2)

  def special_value_from_target("Elm.Kernel.PebbleWatch.storageReadInt", [key, to_msg]),
    do: encoded_cmd_expr(command_kind(:storage_read_int), [key, constructor_tag_expr(to_msg)], 2)

  def special_value_from_target("Elm.Kernel.PebbleWatch.listNthInt", [index, list]) do
    %{
      op: :runtime_call,
      function: "elmc_list_nth_int_default_boxed",
      args: [list, index, %{op: :int_literal, value: 0}]
    }
  end

  def special_value_from_target("Pebble.Cmd.storageDelete", args),
    do: encoded_cmd_expr(command_kind(:storage_delete), args, 1)

  def special_value_from_target("Pebble.Storage.delete", args),
    do: encoded_cmd_expr(command_kind(:storage_delete), args, 1)

  def special_value_from_target("Elm.Kernel.PebbleWatch.storageDelete", args),
    do: encoded_cmd_expr(command_kind(:storage_delete), args, 1)

  def special_value_from_target("Pebble.Storage.writeString", args),
    do: encoded_cmd_expr(command_kind(:storage_write_string), args, 2)

  def special_value_from_target("Elm.Kernel.PebbleWatch.storageWriteString", args),
    do: encoded_cmd_expr(command_kind(:storage_write_string), args, 2)

  def special_value_from_target("Pebble.Storage.readString", [key, to_msg]),
    do:
      encoded_cmd_expr(command_kind(:storage_read_string), [key, constructor_tag_expr(to_msg)], 2)

  def special_value_from_target("Elm.Kernel.PebbleWatch.storageReadString", [key, to_msg]),
    do:
      encoded_cmd_expr(command_kind(:storage_read_string), [key, constructor_tag_expr(to_msg)], 2)

  def special_value_from_target("Random.generate", [to_msg, _generator]),
    do: encoded_cmd_expr(command_kind(:random_generate), [constructor_tag_expr(to_msg)], 1)

  def special_value_from_target("Elm.Kernel.Random.generate", [to_msg, _generator]),
    do: encoded_cmd_expr(command_kind(:random_generate), [constructor_tag_expr(to_msg)], 1)

  def special_value_from_target("Pebble.Internal.Companion.companionSend", args),
    do: encoded_cmd_expr(command_kind(:companion_send), args, 2)

  def special_value_from_target("Elm.Kernel.PebbleWatch.companionSend", args),
    do: encoded_cmd_expr(command_kind(:companion_send), args, 2)

  def special_value_from_target("Pebble.Light.interaction", []),
    do: encoded_cmd_expr(command_kind(:backlight), [%{op: :int_literal, value: 0}], 1)

  def special_value_from_target("Pebble.Light.disable", []),
    do: encoded_cmd_expr(command_kind(:backlight), [%{op: :int_literal, value: 1}], 1)

  def special_value_from_target("Pebble.Light.enable", []),
    do: encoded_cmd_expr(command_kind(:backlight), [%{op: :int_literal, value: 2}], 1)

  def special_value_from_target("Pebble.Cmd.backlight", [mode]),
    do: %{op: :runtime_call, function: "elmc_cmd_backlight_from_maybe", args: [mode]}

  def special_value_from_target("Elm.Kernel.PebbleWatch.backlight", [mode]),
    do: %{op: :runtime_call, function: "elmc_cmd_backlight_from_maybe", args: [mode]}

  def special_value_from_target("Pebble.Cmd.getCurrentTimeString", [to_msg]),
    do: encoded_to_msg_cmd(:get_current_time_string, to_msg)

  def special_value_from_target("Pebble.Time.currentTimeString", [to_msg]),
    do: encoded_to_msg_cmd(:get_current_time_string, to_msg)

  def special_value_from_target("Elm.Kernel.PebbleWatch.getCurrentTimeString", [to_msg]),
    do: encoded_to_msg_cmd(:get_current_time_string, to_msg)

  def special_value_from_target("Pebble.Cmd.getCurrentDateTime", [to_msg]),
    do: encoded_to_msg_cmd(:get_current_date_time, to_msg)

  def special_value_from_target("Pebble.Time.currentDateTime", [to_msg]),
    do: encoded_to_msg_cmd(:get_current_date_time, to_msg)

  def special_value_from_target("Elm.Kernel.PebbleWatch.getCurrentDateTime", [to_msg]),
    do: encoded_to_msg_cmd(:get_current_date_time, to_msg)

  def special_value_from_target("Pebble.System.batteryLevel", [to_msg]),
    do: encoded_to_msg_cmd(:get_battery_level, to_msg)

  def special_value_from_target("Elm.Kernel.PebbleWatch.getBatteryLevel", [to_msg]),
    do: encoded_to_msg_cmd(:get_battery_level, to_msg)

  def special_value_from_target("Pebble.System.connectionStatus", [to_msg]),
    do: encoded_to_msg_cmd(:get_connection_status, to_msg)

  def special_value_from_target("Elm.Kernel.PebbleWatch.getConnectionStatus", [to_msg]),
    do: encoded_to_msg_cmd(:get_connection_status, to_msg)

  def special_value_from_target("Elm.Kernel.PebbleWatch.healthSupported", [to_msg]),
    do:
      encoded_cmd_expr(
        command_kind(:health_supported),
        [constructor_tag_expr(to_msg)],
        1
      )

  def special_value_from_target("Elm.Kernel.PebbleWatch.healthValue", [metric, to_msg]),
    do:
      encoded_cmd_expr(
        command_kind(:health_value),
        [metric, constructor_tag_expr(to_msg)],
        2
      )

  def special_value_from_target("Elm.Kernel.PebbleWatch.healthSumToday", [metric, to_msg]),
    do:
      encoded_cmd_expr(
        command_kind(:health_sum_today),
        [metric, constructor_tag_expr(to_msg)],
        2
      )

  def special_value_from_target("Elm.Kernel.PebbleWatch.healthSum", [
        metric,
        start_seconds,
        end_seconds,
        to_msg
      ]),
      do:
        encoded_cmd_expr(
          command_kind(:health_sum),
          [metric, start_seconds, end_seconds, constructor_tag_expr(to_msg)],
          4
        )

  def special_value_from_target("Elm.Kernel.PebbleWatch.healthAccessible", [
        metric,
        start_seconds,
        end_seconds,
        to_msg
      ]),
      do:
        encoded_cmd_expr(
          command_kind(:health_accessible),
          [metric, start_seconds, end_seconds, constructor_tag_expr(to_msg)],
          4
        )

  def special_value_from_target("Pebble.Cmd.getClockStyle24h", [to_msg]),
    do: encoded_to_msg_cmd(:get_clock_style_24h, to_msg)

  def special_value_from_target("Pebble.Time.clockStyle24h", [to_msg]),
    do: encoded_to_msg_cmd(:get_clock_style_24h, to_msg)

  def special_value_from_target("Elm.Kernel.PebbleWatch.getClockStyle24h", [to_msg]),
    do: encoded_to_msg_cmd(:get_clock_style_24h, to_msg)

  def special_value_from_target("Pebble.Cmd.getTimezoneIsSet", [to_msg]),
    do: encoded_to_msg_cmd(:get_timezone_is_set, to_msg)

  def special_value_from_target("Pebble.Time.timezoneIsSet", [to_msg]),
    do: encoded_to_msg_cmd(:get_timezone_is_set, to_msg)

  def special_value_from_target("Elm.Kernel.PebbleWatch.getTimezoneIsSet", [to_msg]),
    do: encoded_to_msg_cmd(:get_timezone_is_set, to_msg)

  def special_value_from_target("Pebble.Cmd.getTimezone", [to_msg]),
    do: encoded_to_msg_cmd(:get_timezone, to_msg)

  def special_value_from_target("Pebble.Time.timezone", [to_msg]),
    do: encoded_to_msg_cmd(:get_timezone, to_msg)

  def special_value_from_target("Elm.Kernel.PebbleWatch.getTimezone", [to_msg]),
    do: encoded_to_msg_cmd(:get_timezone, to_msg)

  def special_value_from_target("Pebble.Cmd.getWatchModel", [to_msg]),
    do: encoded_to_msg_cmd(:get_watch_model, to_msg)

  def special_value_from_target("Pebble.WatchInfo.getModel", [to_msg]),
    do: encoded_to_msg_cmd(:get_watch_model, to_msg)

  def special_value_from_target("Elm.Kernel.PebbleWatch.getWatchModel", [to_msg]),
    do: encoded_to_msg_cmd(:get_watch_model, to_msg)

  def special_value_from_target("Pebble.Cmd.getFirmwareVersion", [to_msg]),
    do: encoded_to_msg_cmd(:get_firmware_version, to_msg)

  def special_value_from_target("Pebble.WatchInfo.getFirmwareVersion", [to_msg]),
    do: encoded_to_msg_cmd(:get_firmware_version, to_msg)

  def special_value_from_target("Elm.Kernel.PebbleWatch.getFirmwareVersion", [to_msg]),
    do: encoded_to_msg_cmd(:get_firmware_version, to_msg)

  def special_value_from_target("Pebble.WatchInfo.getColor", [to_msg]),
    do: encoded_to_msg_cmd(:get_watch_color, to_msg)

  def special_value_from_target("Elm.Kernel.PebbleWatch.getColor", [to_msg]),
    do: encoded_to_msg_cmd(:get_watch_color, to_msg)

  def special_value_from_target("Elm.Kernel.PebbleWatch.wakeupScheduleAfterSeconds", args),
    do: encoded_cmd_expr(command_kind(:wakeup_schedule_after_seconds), args, 1)

  def special_value_from_target("Elm.Kernel.PebbleWatch.wakeupCancel", args),
    do: encoded_cmd_expr(command_kind(:wakeup_cancel), args, 1)

  def special_value_from_target("Elm.Kernel.PebbleWatch.logInfoCode", args),
    do: encoded_cmd_expr(command_kind(:log_info_code), args, 1)

  def special_value_from_target("Elm.Kernel.PebbleWatch.logWarnCode", args),
    do: encoded_cmd_expr(command_kind(:log_warn_code), args, 1)

  def special_value_from_target("Elm.Kernel.PebbleWatch.logErrorCode", args),
    do: encoded_cmd_expr(command_kind(:log_error_code), args, 1)

  def special_value_from_target("Pebble.Cmd.vibesCancel", _args),
    do: command_kind_expr(:vibes_cancel)

  def special_value_from_target("Pebble.Vibes.cancel", _args),
    do: command_kind_expr(:vibes_cancel)

  def special_value_from_target("Elm.Kernel.PebbleWatch.vibesCancel", _args),
    do: command_kind_expr(:vibes_cancel)

  def special_value_from_target("Pebble.Cmd.vibesShortPulse", _args),
    do: command_kind_expr(:vibes_short_pulse)

  def special_value_from_target("Pebble.Vibes.shortPulse", _args),
    do: command_kind_expr(:vibes_short_pulse)

  def special_value_from_target("Elm.Kernel.PebbleWatch.vibesShortPulse", _args),
    do: command_kind_expr(:vibes_short_pulse)

  def special_value_from_target("Pebble.Cmd.vibesLongPulse", _args),
    do: command_kind_expr(:vibes_long_pulse)

  def special_value_from_target("Pebble.Vibes.longPulse", _args),
    do: command_kind_expr(:vibes_long_pulse)

  def special_value_from_target("Elm.Kernel.PebbleWatch.vibesLongPulse", _args),
    do: command_kind_expr(:vibes_long_pulse)

  def special_value_from_target("Pebble.Cmd.vibesDoublePulse", _args),
    do: command_kind_expr(:vibes_double_pulse)

  def special_value_from_target("Pebble.Vibes.doublePulse", _args),
    do: command_kind_expr(:vibes_double_pulse)

  def special_value_from_target("Elm.Kernel.PebbleWatch.vibesDoublePulse", _args),
    do: command_kind_expr(:vibes_double_pulse)

  def special_value_from_target("Pebble.Vibes.pattern", [segments]),
    do: encoded_cmd_expr(command_kind(:vibes_custom_pattern), [segments], 1)

  def special_value_from_target("Elm.Kernel.PebbleWatch.vibesCustomPattern", [segments]),
    do: encoded_cmd_expr(command_kind(:vibes_custom_pattern), [segments], 1)

  def special_value_from_target("Pebble.DataLog.logBytes", [tag, bytes]),
    do: encoded_cmd_expr(command_kind(:data_log_bytes), [tag, bytes], 2)

  def special_value_from_target("Elm.Kernel.PebbleWatch.dataLogBytes", [tag, bytes]),
    do: encoded_cmd_expr(command_kind(:data_log_bytes), [tag, bytes], 2)

  def special_value_from_target("Pebble.DataLog.logInt32", [tag, value]),
    do: encoded_cmd_expr(command_kind(:data_log_int32), [tag, value], 2)

  def special_value_from_target("Elm.Kernel.PebbleWatch.dataLogInt32", [tag, value]),
    do: encoded_cmd_expr(command_kind(:data_log_int32), [tag, value], 2)

  def special_value_from_target("Pebble.Compass.current", [to_msg]),
    do: encoded_cmd_expr(command_kind(:compass_peek), [constructor_tag_expr(to_msg)], 1)

  def special_value_from_target("Elm.Kernel.PebbleWatch.compassCurrent", [to_msg]),
    do: encoded_cmd_expr(command_kind(:compass_peek), [constructor_tag_expr(to_msg)], 1)

  def special_value_from_target("Pebble.Dictation.start", _args),
    do: command_kind_expr(:dictation_start)

  def special_value_from_target("Elm.Kernel.PebbleWatch.dictationStart", _args),
    do: command_kind_expr(:dictation_start)

  def special_value_from_target("Pebble.Dictation.stop", _args),
    do: command_kind_expr(:dictation_stop)

  def special_value_from_target("Elm.Kernel.PebbleWatch.dictationStop", _args),
    do: command_kind_expr(:dictation_stop)

  def special_value_from_target("Pebble.Events.onSecondChange", args),
    do: subscription_special_value("Pebble.Events.onSecondChange", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onSecondChange", args),
    do: subscription_special_value("Elm.Kernel.PebbleWatch.onSecondChange", args)

  def special_value_from_target("Pebble.Frame.every", args),
    do: subscription_special_value("Pebble.Frame.every", args)

  def special_value_from_target("Pebble.Frame.atFps", args),
    do: subscription_special_value("Pebble.Frame.atFps", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onFrame", args),
    do: subscription_special_value("Elm.Kernel.PebbleWatch.onFrame", args)

  def special_value_from_target("Pebble.Events.onHourChange", args),
    do: subscription_special_value("Pebble.Events.onHourChange", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onHourChange", args),
    do: subscription_special_value("Elm.Kernel.PebbleWatch.onHourChange", args)

  def special_value_from_target("Pebble.Events.onMinuteChange", args),
    do: subscription_special_value("Pebble.Events.onMinuteChange", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onMinuteChange", args),
    do: subscription_special_value("Elm.Kernel.PebbleWatch.onMinuteChange", args)

  def special_value_from_target("Pebble.Events.onDayChange", args),
    do: subscription_special_value("Pebble.Events.onDayChange", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onDayChange", args),
    do: subscription_special_value("Elm.Kernel.PebbleWatch.onDayChange", args)

  def special_value_from_target("Pebble.Events.onMonthChange", args),
    do: subscription_special_value("Pebble.Events.onMonthChange", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onMonthChange", args),
    do: subscription_special_value("Elm.Kernel.PebbleWatch.onMonthChange", args)

  def special_value_from_target("Pebble.Events.onYearChange", args),
    do: subscription_special_value("Pebble.Events.onYearChange", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onYearChange", args),
    do: subscription_special_value("Elm.Kernel.PebbleWatch.onYearChange", args)

  def special_value_from_target("Pebble.Button.onPress", args),
    do: subscription_special_value("Pebble.Button.onPress", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onButtonUp", args),
    do: subscription_special_value("Elm.Kernel.PebbleWatch.onButtonUp", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onButtonSelect", args),
    do: subscription_special_value("Elm.Kernel.PebbleWatch.onButtonSelect", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onButtonDown", args),
    do: subscription_special_value("Elm.Kernel.PebbleWatch.onButtonDown", args)

  def special_value_from_target("Pebble.Button.on", args),
    do: subscription_special_value("Pebble.Button.on", args)

  def special_value_from_target("Pebble.Button.onRelease", args),
    do: subscription_special_value("Pebble.Button.onRelease", args)

  def special_value_from_target("Pebble.Button.onLongPress", args),
    do: subscription_special_value("Pebble.Button.onLongPress", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onButtonRaw", args),
    do: subscription_special_value("Elm.Kernel.PebbleWatch.onButtonRaw", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onButtonLongUp", args),
    do: subscription_special_value("Elm.Kernel.PebbleWatch.onButtonLongUp", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onButtonLongSelect", args),
    do: subscription_special_value("Elm.Kernel.PebbleWatch.onButtonLongSelect", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onButtonLongDown", args),
    do: subscription_special_value("Elm.Kernel.PebbleWatch.onButtonLongDown", args)

  def special_value_from_target("Pebble.Accel.onTap", args),
    do: subscription_special_value("Pebble.Accel.onTap", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onAccelTap", args),
    do: subscription_special_value("Elm.Kernel.PebbleWatch.onAccelTap", args)

  def special_value_from_target("Pebble.Accel.onData", args),
    do: subscription_special_value("Pebble.Accel.onData", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onAccelData", args),
    do: subscription_special_value("Elm.Kernel.PebbleWatch.onAccelData", args)

  def special_value_from_target("Pebble.System.onBatteryChange", args),
    do: subscription_special_value("Pebble.System.onBatteryChange", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onBatteryChange", args),
    do: subscription_special_value("Elm.Kernel.PebbleWatch.onBatteryChange", args)

  def special_value_from_target("Pebble.System.onConnectionChange", args),
    do: subscription_special_value("Pebble.System.onConnectionChange", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onConnectionChange", args),
    do: subscription_special_value("Elm.Kernel.PebbleWatch.onConnectionChange", args)

  def special_value_from_target("Pebble.Health.onEvent", args),
    do: subscription_special_value("Pebble.Health.onEvent", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onHealthEvent", args),
    do: subscription_special_value("Elm.Kernel.PebbleWatch.onHealthEvent", args)

  def special_value_from_target("Pebble.Health.supported", args),
    do: special_value_from_target("Elm.Kernel.PebbleWatch.healthSupported", args)

  def special_value_from_target("Pebble.Health.value", [metric, to_msg]),
    do:
      special_value_from_target("Elm.Kernel.PebbleWatch.healthValue", [
        health_metric_to_kernel_expr(metric),
        to_msg
      ])

  def special_value_from_target("Pebble.Health.sumToday", [metric, to_msg]),
    do:
      special_value_from_target("Elm.Kernel.PebbleWatch.healthSumToday", [
        health_metric_to_kernel_expr(metric),
        to_msg
      ])

  def special_value_from_target("Pebble.Health.sum", [metric, start_seconds, end_seconds, to_msg]),
      do:
        special_value_from_target("Elm.Kernel.PebbleWatch.healthSum", [
          health_metric_to_kernel_expr(metric),
          start_seconds,
          end_seconds,
          to_msg
        ])

  def special_value_from_target("Pebble.Health.accessible", [
        metric,
        start_seconds,
        end_seconds,
        to_msg
      ]),
      do:
        special_value_from_target("Elm.Kernel.PebbleWatch.healthAccessible", [
          health_metric_to_kernel_expr(metric),
          start_seconds,
          end_seconds,
          to_msg
        ])

  def special_value_from_target("Pebble.AppFocus.onChange", args),
    do: subscription_special_value("Pebble.AppFocus.onChange", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onAppFocusChange", args),
    do: subscription_special_value("Elm.Kernel.PebbleWatch.onAppFocusChange", args)

  def special_value_from_target("Pebble.Compass.onChange", args),
    do: subscription_special_value("Pebble.Compass.onChange", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onCompassChange", args),
    do: subscription_special_value("Elm.Kernel.PebbleWatch.onCompassChange", args)

  def special_value_from_target("Pebble.Dictation.onStatus", args),
    do: subscription_special_value("Pebble.Dictation.onStatus", args)

  def special_value_from_target("Pebble.Dictation.onResult", args),
    do: subscription_special_value("Pebble.Dictation.onResult", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onDictationStatus", args),
    do: subscription_special_value("Elm.Kernel.PebbleWatch.onDictationStatus", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onDictationResult", args),
    do: subscription_special_value("Elm.Kernel.PebbleWatch.onDictationResult", args)

  def special_value_from_target("Pebble.UnobstructedArea.onWillChange", args),
    do: subscription_special_value("Pebble.UnobstructedArea.onWillChange", args)

  def special_value_from_target("Pebble.UnobstructedArea.onChanging", args),
    do: subscription_special_value("Pebble.UnobstructedArea.onChanging", args)

  def special_value_from_target("Pebble.UnobstructedArea.onDidChange", args),
    do: subscription_special_value("Pebble.UnobstructedArea.onDidChange", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onUnobstructedWillChange", args),
    do: subscription_special_value("Elm.Kernel.PebbleWatch.onUnobstructedWillChange", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onUnobstructedChanging", args),
    do: subscription_special_value("Elm.Kernel.PebbleWatch.onUnobstructedChanging", args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.onUnobstructedDidChange", args),
    do: subscription_special_value("Elm.Kernel.PebbleWatch.onUnobstructedDidChange", args)

  def special_value_from_target("Pebble.UnobstructedArea.currentBounds", [to_msg]),
    do:
      encoded_cmd_expr(command_kind(:unobstructed_bounds_peek), [constructor_tag_expr(to_msg)], 1)

  def special_value_from_target("Elm.Kernel.PebbleWatch.unobstructedCurrentBounds", [to_msg]),
    do:
      encoded_cmd_expr(command_kind(:unobstructed_bounds_peek), [constructor_tag_expr(to_msg)], 1)

  def special_value_from_target("Companion.Watch.onPhoneToWatch", args),
    do: subscription_special_value("Companion.Watch.onPhoneToWatch", args)

  def special_value_from_target("Pebble.Events.batch", args),
    do: Subscriptions.subscription_batch_expr(args)

  def special_value_from_target("Elm.Kernel.PebbleWatch.batch", args),
    do: Subscriptions.subscription_batch_expr(args)

  def special_value_from_target("Elm.Kernel.PebblePhone.httpGet", [url, to_msg]),
    do: http_request_constructor_expr("GET", url, to_msg)

  def special_value_from_target("Elm.Kernel.PebblePhone.httpPost", [url, to_msg]),
    do: http_request_constructor_expr("POST", url, to_msg)

  def special_value_from_target("Elm.Kernel.PebblePhone.httpPut", [url, to_msg]),
    do: http_request_constructor_expr("PUT", url, to_msg)

  def special_value_from_target("Elm.Kernel.PebblePhone.httpDelete", [url, to_msg]),
    do: http_request_constructor_expr("DELETE", url, to_msg)

  def special_value_from_target("Elm.Kernel.PebblePhone.httpRequest", [method, url]),
    do: %{op: :qualified_call, target: "Pebble.Http.requestImpl", args: [method, url]}

  def special_value_from_target("Elm.Kernel.PebblePhone.httpWithHeader", [name, value, req]),
    do: %{op: :qualified_call, target: "Pebble.Http.withHeaderImpl", args: [name, value, req]}

  def special_value_from_target("Elm.Kernel.PebblePhone.httpWithTimeout", [timeout, req]),
    do: %{op: :qualified_call, target: "Pebble.Http.withTimeoutImpl", args: [timeout, req]}

  def special_value_from_target("Elm.Kernel.PebblePhone.httpWithBody", [body, req]),
    do: %{op: :qualified_call, target: "Pebble.Http.withBodyImpl", args: [body, req]}

  def special_value_from_target("Elm.Kernel.PebblePhone.httpExpectString", [to_msg, req]),
    do: %{op: :qualified_call, target: "Pebble.Http.expectStringImpl", args: [to_msg, req]}

  def special_value_from_target("Elm.Kernel.PebblePhone.httpExpectJson", [decoder, to_msg, req]),
    do: %{op: :qualified_call, target: "Pebble.Http.expectJsonImpl", args: [decoder, to_msg, req]}

  def special_value_from_target("Elm.Kernel.PebblePhone.httpExpectBytes", [to_msg, req]),
    do: %{op: :qualified_call, target: "Pebble.Http.expectBytesImpl", args: [to_msg, req]}

  def special_value_from_target("Elm.Kernel.PebblePhone.storageSave", [key, value, to_msg]),
    do: %{op: :constructor_call, target: "Pebble.Storage.Save", args: [key, value, to_msg]}

  def special_value_from_target("Elm.Kernel.PebblePhone.storageLoad", [key, to_msg]),
    do: %{op: :constructor_call, target: "Pebble.Storage.Load", args: [key, to_msg]}

  def special_value_from_target("Elm.Kernel.PebblePhone.storageRemove", [key, to_msg]),
    do: %{op: :constructor_call, target: "Pebble.Storage.Remove", args: [key, to_msg]}

  def special_value_from_target("Elm.Kernel.PebblePhone.storageClear", [to_msg]),
    do: %{op: :constructor_call, target: "Pebble.Storage.Clear", args: [to_msg]}

  def special_value_from_target("Elm.Kernel.PebblePhone.storageSaveJson", [key, value, to_msg]),
    do: %{op: :qualified_call, target: "Pebble.Storage.saveJsonImpl", args: [key, value, to_msg]}

  def special_value_from_target("Elm.Kernel.PebblePhone.storageLoadJson", [key, decoder, to_msg]),
    do: %{
      op: :qualified_call,
      target: "Pebble.Storage.loadJsonImpl",
      args: [key, decoder, to_msg]
    }

  def special_value_from_target("Elm.Kernel.PebblePhone.storageSaveInt", [key, value, to_msg]),
    do: %{op: :qualified_call, target: "Pebble.Storage.saveIntImpl", args: [key, value, to_msg]}

  def special_value_from_target("Elm.Kernel.PebblePhone.storageLoadInt", [key, to_msg]),
    do: %{op: :qualified_call, target: "Pebble.Storage.loadIntImpl", args: [key, to_msg]}

  def special_value_from_target("Elm.Kernel.PebblePhone.storageSaveBool", [key, value, to_msg]),
    do: %{op: :qualified_call, target: "Pebble.Storage.saveBoolImpl", args: [key, value, to_msg]}

  def special_value_from_target("Elm.Kernel.PebblePhone.storageLoadBool", [key, to_msg]),
    do: %{op: :qualified_call, target: "Pebble.Storage.loadBoolImpl", args: [key, to_msg]}

  def special_value_from_target("Elm.Kernel.PebblePhone.webSocketConnect", [url, to_msg]),
    do: %{op: :constructor_call, target: "Pebble.WebSocket.Connect", args: [url, to_msg]}

  def special_value_from_target("Elm.Kernel.PebblePhone.webSocketDisconnect", [to_msg]),
    do: %{op: :constructor_call, target: "Pebble.WebSocket.Disconnect", args: [to_msg]}

  def special_value_from_target("Elm.Kernel.PebblePhone.webSocketSend", [message, to_msg]),
    do: %{op: :constructor_call, target: "Pebble.WebSocket.Send", args: [message, to_msg]}

  def special_value_from_target("Elm.Kernel.PebblePhone.webSocketSendJson", [json_data, to_msg]),
    do: %{op: :constructor_call, target: "Pebble.WebSocket.SendJson", args: [json_data, to_msg]}

  def special_value_from_target("Elm.Kernel.PebblePhone.webSocketIsConnected", [state]),
    do: %{op: :qualified_call, target: "Pebble.WebSocket.isConnectedImpl", args: [state]}

  def special_value_from_target("Elm.Kernel.PebblePhone.webSocketGetState", [state]),
    do: %{op: :qualified_call, target: "Pebble.WebSocket.getStateImpl", args: [state]}

  def special_value_from_target("Basics.max", [left, right]),
    do: %{op: :runtime_call, function: "elmc_basics_max", args: [left, right]}

  def special_value_from_target("Basics.min", [left, right]),
    do: %{op: :runtime_call, function: "elmc_basics_min", args: [left, right]}

  def special_value_from_target("Basics.clamp", [low, high, value]),
    do: %{op: :runtime_call, function: "elmc_basics_clamp", args: [low, high, value]}

  def special_value_from_target("Basics.modBy", [base, value]),
    do: %{op: :runtime_call, function: "elmc_basics_mod_by", args: [base, value]}

  def special_value_from_target("Basics.remainderBy", [base, value]),
    do: %{op: :runtime_call, function: "elmc_basics_remainder_by", args: [base, value]}

  def special_value_from_target("Bitwise.and", [left, right]),
    do: %{op: :runtime_call, function: "elmc_bitwise_and", args: [left, right]}

  def special_value_from_target("Bitwise.or", [left, right]),
    do: %{op: :runtime_call, function: "elmc_bitwise_or", args: [left, right]}

  def special_value_from_target("Bitwise.xor", [left, right]),
    do: %{op: :runtime_call, function: "elmc_bitwise_xor", args: [left, right]}

  def special_value_from_target("Bitwise.complement", [value]),
    do: %{op: :runtime_call, function: "elmc_bitwise_complement", args: [value]}

  def special_value_from_target("Bitwise.shiftLeftBy", [bits, value]),
    do: %{op: :runtime_call, function: "elmc_bitwise_shift_left_by", args: [bits, value]}

  def special_value_from_target("Bitwise.shiftRightBy", [bits, value]),
    do: %{op: :runtime_call, function: "elmc_bitwise_shift_right_by", args: [bits, value]}

  def special_value_from_target("Bitwise.shiftRightZfBy", [bits, value]),
    do: %{op: :runtime_call, function: "elmc_bitwise_shift_right_zf_by", args: [bits, value]}

  def special_value_from_target("Char.toCode", [value]),
    do: %{op: :runtime_call, function: "elmc_char_to_code", args: [value]}

  def special_value_from_target("Debug.log", [label, value]),
    do: %{op: :runtime_call, function: "elmc_debug_log", args: [label, value]}

  def special_value_from_target("Debug.todo", [label]),
    do: %{op: :runtime_call, function: "elmc_debug_todo", args: [label]}

  def special_value_from_target("Debug.toString", [value]),
    do: %{op: :runtime_call, function: "elmc_debug_to_string", args: [value]}

  def special_value_from_target("String.append", [left, right]),
    do: %{op: :runtime_call, function: "elmc_append", args: [left, right]}

  def special_value_from_target("String.isEmpty", [value]),
    do: %{op: :runtime_call, function: "elmc_string_is_empty", args: [value]}

  def special_value_from_target("Tuple.pair", [left, right]),
    do: %{op: :tuple2, left: left, right: right}

  def special_value_from_target("Tuple.pair", []),
    do: %{
      op: :lambda,
      args: ["__a", "__b"],
      body: %{op: :tuple2, left: %{op: :var, name: "__a"}, right: %{op: :var, name: "__b"}}
    }

  def special_value_from_target("Tuple.pair", [left]),
    do: %{
      op: :lambda,
      args: ["__b"],
      body: %{op: :tuple2, left: left, right: %{op: :var, name: "__b"}}
    }

  def special_value_from_target("Dict.empty", []), do: %{op: :list_literal, items: []}

  def special_value_from_target("Dict.fromList", [items]),
    do: %{op: :runtime_call, function: "elmc_dict_from_list", args: [items]}

  def special_value_from_target("Dict.insert", [key, value, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_insert", args: [key, value, dict]}

  def special_value_from_target("Dict.get", [key, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_get", args: [key, dict]}

  def special_value_from_target("Dict.member", [key, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_member", args: [key, dict]}

  def special_value_from_target("Dict.size", [dict]),
    do: %{op: :runtime_call, function: "elmc_dict_size", args: [dict]}

  def special_value_from_target("Set.empty", []), do: %{op: :list_literal, items: []}

  def special_value_from_target("Set.fromList", [items]),
    do: %{op: :runtime_call, function: "elmc_set_from_list", args: [items]}

  def special_value_from_target("Set.insert", [value, set]),
    do: %{op: :runtime_call, function: "elmc_set_insert", args: [value, set]}

  def special_value_from_target("Set.insert", []),
    do: runtime_fn_lambda("elmc_set_insert", ["__value", "__set"])

  def special_value_from_target("Set.member", [value, set]),
    do: %{op: :runtime_call, function: "elmc_set_member", args: [value, set]}

  def special_value_from_target("Set.size", [set]),
    do: %{op: :runtime_call, function: "elmc_set_size", args: [set]}

  def special_value_from_target("Array.empty", []),
    do: %{op: :runtime_call, function: "elmc_array_empty", args: []}

  def special_value_from_target("Array.fromList", [items]),
    do: %{op: :runtime_call, function: "elmc_array_from_list", args: [items]}

  def special_value_from_target("Array.length", [array]),
    do: %{op: :runtime_call, function: "elmc_array_length", args: [array]}

  def special_value_from_target("Array.get", [index, array]),
    do: %{op: :runtime_call, function: "elmc_array_get", args: [index, array]}

  def special_value_from_target("Array.set", [index, value, array]),
    do: %{op: :runtime_call, function: "elmc_array_set", args: [index, value, array]}

  def special_value_from_target("Array.push", [value, array]),
    do: %{op: :runtime_call, function: "elmc_array_push", args: [value, array]}

  def special_value_from_target("Task.succeed", [value]),
    do: %{op: :runtime_call, function: "elmc_task_succeed", args: [value]}

  def special_value_from_target("Task.fail", [value]),
    do: %{op: :runtime_call, function: "elmc_task_fail", args: [value]}

  def special_value_from_target("Task.map", [f]),
    do: %{
      op: :lambda,
      args: ["__t"],
      body: %{op: :runtime_call, function: "elmc_task_map", args: [f, %{op: :var, name: "__t"}]}
    }

  def special_value_from_target("Task.map2", [f]),
    do: %{
      op: :lambda,
      args: ["__a", "__b"],
      body: %{
        op: :runtime_call,
        function: "elmc_task_map2",
        args: [f, %{op: :var, name: "__a"}, %{op: :var, name: "__b"}]
      }
    }

  def special_value_from_target("Task.map2", [f, a]),
    do: %{
      op: :lambda,
      args: ["__b"],
      body: %{
        op: :runtime_call,
        function: "elmc_task_map2",
        args: [f, a, %{op: :var, name: "__b"}]
      }
    }

  def special_value_from_target("Task.andThen", [f]),
    do: %{
      op: :lambda,
      args: ["__t"],
      body: %{
        op: :runtime_call,
        function: "elmc_task_and_then",
        args: [f, %{op: :var, name: "__t"}]
      }
    }

  def special_value_from_target("Process.spawn", [task]),
    do: %{op: :runtime_call, function: "elmc_process_spawn", args: [task]}

  def special_value_from_target("Process.sleep", [milliseconds]),
    do: %{op: :runtime_call, function: "elmc_process_sleep", args: [milliseconds]}

  def special_value_from_target("Process.kill", [pid]),
    do: %{op: :runtime_call, function: "elmc_process_kill", args: [pid]}

  def special_value_from_target("Elm.Kernel.Time.nowMillis", [_unit]),
    do: %{op: :runtime_call, function: "elmc_time_now_millis", args: []}

  def special_value_from_target("Elm.Kernel.Time.zoneOffsetMinutes", [_unit]),
    do: %{op: :runtime_call, function: "elmc_time_zone_offset_minutes", args: []}

  def special_value_from_target("Elm.Kernel.Time.every", _args),
    do: %{op: :int_literal, value: 1}

  def special_value_from_target("Cmd.none", _args), do: %{op: :int_literal, value: 0}

  def special_value_from_target("Platform.Cmd.none", _args),
    do: command_kind_expr(:none)

  def special_value_from_target("Cmd.batch", [%{op: :list_literal, items: []}]),
    do: %{op: :int_literal, value: 0}

  def special_value_from_target("Cmd.batch", [%{op: :list_literal, items: [command]}]),
    do: command

  def special_value_from_target("Cmd.batch", [commands]),
    do: %{op: :runtime_call, function: "elmc_cmd_batch", args: [commands]}

  def special_value_from_target("Cmd.map", [f, cmd]),
    do: %{op: :runtime_call, function: "elmc_cmd_map", args: [f, cmd]}

  def special_value_from_target("Pebble.Cmd.batch", args),
    do: special_value_from_target("Cmd.batch", args)

  def special_value_from_target("Sub.none", _args), do: %{op: :int_literal, value: 0}

  def special_value_from_target("Platform.Sub.none", _args),
    do: %{op: :int_literal, value: 0}

  def special_value_from_target("Sub.batch", args) do
    case Subscriptions.subscription_batch_expr(args) do
      %{op: :list_literal, items: items} = list_expr ->
        if Enum.any?(items, &match?(%{op: :pebble_sub}, &1)) do
          list_expr
        else
          %{op: :runtime_call, function: "elmc_sub_batch", args: [list_expr]}
        end

      nil ->
        case args do
          [%{op: :list_literal, items: []}] ->
            %{op: :int_literal, value: 0}

          [%{op: :list_literal, items: [single]}] ->
            single

          [subs] ->
            %{op: :runtime_call, function: "elmc_sub_batch", args: [subs]}

          _ ->
            nil
        end
    end
  end

  def special_value_from_target("Sub.map", [f, sub]),
    do: %{op: :runtime_call, function: "elmc_sub_map", args: [f, sub]}

  def special_value_from_target("Pebble.Platform.application", _args),
    do: %{op: :int_literal, value: 0}

  def special_value_from_target("Platform.worker", _args),
    do: %{op: :int_literal, value: 0}

  def special_value_from_target("Pebble.Platform.watchface", _args),
    do: %{op: :int_literal, value: 0}

  def special_value_from_target("Pebble.Platform.displayShapeIsRound", [shape]),
    do: platform_union_is_constructor(shape, "Round", 2, "PBL_ROUND")

  def special_value_from_target("Pebble.Platform.colorCapabilityIsColor", [capability]),
    do: platform_union_is_constructor(capability, "Color", 2, "PBL_COLOR")

  # --- Partial application: zero-arg references to known stdlib functions ---
  # When a qualified call is used as a value (0 args), wrap it in a lambda.
  def special_value_from_target("List.head", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_head", args: [%{op: :var, name: "__l"}]}
    }

  def special_value_from_target("List.tail", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_tail", args: [%{op: :var, name: "__l"}]}
    }

  def special_value_from_target("List.reverse", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_reverse", args: [%{op: :var, name: "__l"}]}
    }

  def special_value_from_target("List.length", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_length", args: [%{op: :var, name: "__l"}]}
    }

  def special_value_from_target("List.isEmpty", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_is_empty", args: [%{op: :var, name: "__l"}]}
    }

  def special_value_from_target("List.sum", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_sum", args: [%{op: :var, name: "__l"}]}
    }

  def special_value_from_target("List.product", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_product", args: [%{op: :var, name: "__l"}]}
    }

  def special_value_from_target("List.maximum", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_maximum", args: [%{op: :var, name: "__l"}]}
    }

  def special_value_from_target("List.minimum", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_minimum", args: [%{op: :var, name: "__l"}]}
    }

  def special_value_from_target("List.sort", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_sort", args: [%{op: :var, name: "__l"}]}
    }

  def special_value_from_target("List.concat", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_concat", args: [%{op: :var, name: "__l"}]}
    }

  def special_value_from_target("Maybe.withDefault", [default_val]),
    do: %{
      op: :lambda,
      args: ["__m"],
      body: %{
        op: :runtime_call,
        function: "elmc_maybe_with_default",
        args: [default_val, %{op: :var, name: "__m"}]
      }
    }

  def special_value_from_target("Maybe.map", [f]),
    do: %{
      op: :lambda,
      args: ["__m"],
      body: %{op: :runtime_call, function: "elmc_maybe_map", args: [f, %{op: :var, name: "__m"}]}
    }

  def special_value_from_target("Maybe.andThen", [f]),
    do: %{
      op: :lambda,
      args: ["__m"],
      body: %{
        op: :runtime_call,
        function: "elmc_maybe_and_then",
        args: [f, %{op: :var, name: "__m"}]
      }
    }

  def special_value_from_target("Result.map", [f]),
    do: %{
      op: :lambda,
      args: ["__r"],
      body: %{op: :runtime_call, function: "elmc_result_map", args: [f, %{op: :var, name: "__r"}]}
    }

  def special_value_from_target("Result.mapError", [f]),
    do: %{
      op: :lambda,
      args: ["__r"],
      body: %{
        op: :runtime_call,
        function: "elmc_result_map_error",
        args: [f, %{op: :var, name: "__r"}]
      }
    }

  def special_value_from_target("Result.andThen", [f]),
    do: %{
      op: :lambda,
      args: ["__r"],
      body: %{
        op: :runtime_call,
        function: "elmc_result_and_then",
        args: [f, %{op: :var, name: "__r"}]
      }
    }

  def special_value_from_target("Result.withDefault", [default_val]),
    do: %{
      op: :lambda,
      args: ["__r"],
      body: %{
        op: :runtime_call,
        function: "elmc_result_with_default",
        args: [default_val, %{op: :var, name: "__r"}]
      }
    }

  def special_value_from_target("Result.toMaybe", []),
    do: %{
      op: :lambda,
      args: ["__r"],
      body: %{
        op: :runtime_call,
        function: "elmc_result_to_maybe",
        args: [%{op: :var, name: "__r"}]
      }
    }

  def special_value_from_target("String.fromInt", []),
    do: %{
      op: :lambda,
      args: ["__n"],
      body: %{
        op: :runtime_call,
        function: "elmc_string_from_int",
        args: [%{op: :var, name: "__n"}]
      }
    }

  def special_value_from_target("String.fromFloat", []),
    do: %{
      op: :lambda,
      args: ["__f"],
      body: %{
        op: :runtime_call,
        function: "elmc_string_from_float",
        args: [%{op: :var, name: "__f"}]
      }
    }

  def special_value_from_target("String.toInt", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{op: :runtime_call, function: "elmc_string_to_int", args: [%{op: :var, name: "__s"}]}
    }

  def special_value_from_target("String.toFloat", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{
        op: :runtime_call,
        function: "elmc_string_to_float",
        args: [%{op: :var, name: "__s"}]
      }
    }

  def special_value_from_target("String.isEmpty", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{
        op: :runtime_call,
        function: "elmc_string_is_empty",
        args: [%{op: :var, name: "__s"}]
      }
    }

  def special_value_from_target("String.length", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{
        op: :runtime_call,
        function: "elmc_string_length_val",
        args: [%{op: :var, name: "__s"}]
      }
    }

  def special_value_from_target("String.reverse", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{
        op: :runtime_call,
        function: "elmc_string_reverse",
        args: [%{op: :var, name: "__s"}]
      }
    }

  def special_value_from_target("String.toUpper", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{
        op: :runtime_call,
        function: "elmc_string_to_upper",
        args: [%{op: :var, name: "__s"}]
      }
    }

  def special_value_from_target("String.toLower", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{
        op: :runtime_call,
        function: "elmc_string_to_lower",
        args: [%{op: :var, name: "__s"}]
      }
    }

  def special_value_from_target("String.trim", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{op: :runtime_call, function: "elmc_string_trim", args: [%{op: :var, name: "__s"}]}
    }

  def special_value_from_target("String.words", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{op: :runtime_call, function: "elmc_string_words", args: [%{op: :var, name: "__s"}]}
    }

  def special_value_from_target("String.lines", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{op: :runtime_call, function: "elmc_string_lines", args: [%{op: :var, name: "__s"}]}
    }

  def special_value_from_target("Basics.identity", []),
    do: %{op: :lambda, args: ["__x"], body: %{op: :var, name: "__x"}}

  def special_value_from_target("Basics.always", []),
    do: %{op: :lambda, args: ["__a", "__b"], body: %{op: :var, name: "__a"}}

  def special_value_from_target("Basics.always", [x]),
    do: %{op: :lambda, args: ["__ignored"], body: x}

  def special_value_from_target("Basics.negate", []),
    do: %{
      op: :lambda,
      args: ["__x"],
      body: %{op: :runtime_call, function: "elmc_basics_negate", args: [%{op: :var, name: "__x"}]}
    }

  def special_value_from_target("Basics.not", []),
    do: %{
      op: :lambda,
      args: ["__x"],
      body: %{op: :runtime_call, function: "elmc_basics_not", args: [%{op: :var, name: "__x"}]}
    }

  def special_value_from_target("Basics.abs", []),
    do: %{
      op: :lambda,
      args: ["__x"],
      body: %{op: :runtime_call, function: "elmc_basics_abs", args: [%{op: :var, name: "__x"}]}
    }

  def special_value_from_target("Basics.toFloat", []),
    do: %{
      op: :lambda,
      args: ["__x"],
      body: %{
        op: :runtime_call,
        function: "elmc_basics_to_float",
        args: [%{op: :var, name: "__x"}]
      }
    }

  def special_value_from_target("Basics.sqrt", []), do: unary_runtime_lambda("elmc_basics_sqrt")

  def special_value_from_target("Basics.logBase", []),
    do: binary_runtime_lambda("elmc_basics_log_base")

  def special_value_from_target("Basics.logBase", [base]),
    do: bound_binary_runtime_lambda("elmc_basics_log_base", base)

  def special_value_from_target("Basics.cos", []), do: unary_runtime_lambda("elmc_basics_cos")
  def special_value_from_target("Basics.sin", []), do: unary_runtime_lambda("elmc_basics_sin")
  def special_value_from_target("Basics.tan", []), do: unary_runtime_lambda("elmc_basics_tan")
  def special_value_from_target("Basics.acos", []), do: unary_runtime_lambda("elmc_basics_acos")
  def special_value_from_target("Basics.asin", []), do: unary_runtime_lambda("elmc_basics_asin")
  def special_value_from_target("Basics.atan", []), do: unary_runtime_lambda("elmc_basics_atan")

  def special_value_from_target("Basics.atan2", []),
    do: binary_runtime_lambda("elmc_basics_atan2")

  def special_value_from_target("Basics.atan2", [y]),
    do: bound_binary_runtime_lambda("elmc_basics_atan2", y)

  def special_value_from_target("Basics.degrees", []),
    do: unary_runtime_lambda("elmc_basics_degrees")

  def special_value_from_target("Basics.radians", []),
    do: unary_runtime_lambda("elmc_basics_radians")

  def special_value_from_target("Basics.turns", []),
    do: unary_runtime_lambda("elmc_basics_turns")

  def special_value_from_target("Basics.fromPolar", []),
    do: unary_runtime_lambda("elmc_basics_from_polar")

  def special_value_from_target("Basics.toPolar", []),
    do: unary_runtime_lambda("elmc_basics_to_polar")

  def special_value_from_target("Basics.isNaN", []),
    do: unary_runtime_lambda("elmc_basics_is_nan")

  def special_value_from_target("Basics.isInfinite", []),
    do: unary_runtime_lambda("elmc_basics_is_infinite")

  def special_value_from_target("Basics.round", []),
    do: %{
      op: :lambda,
      args: ["__x"],
      body: %{op: :runtime_call, function: "elmc_basics_round", args: [%{op: :var, name: "__x"}]}
    }

  def special_value_from_target("Basics.floor", []),
    do: %{
      op: :lambda,
      args: ["__x"],
      body: %{op: :runtime_call, function: "elmc_basics_floor", args: [%{op: :var, name: "__x"}]}
    }

  def special_value_from_target("Basics.ceiling", []),
    do: %{
      op: :lambda,
      args: ["__x"],
      body: %{
        op: :runtime_call,
        function: "elmc_basics_ceiling",
        args: [%{op: :var, name: "__x"}]
      }
    }

  def special_value_from_target("Basics.max", []), do: binary_runtime_lambda("elmc_basics_max")

  def special_value_from_target("Basics.max", [left]),
    do: bound_binary_runtime_lambda("elmc_basics_max", left)

  def special_value_from_target("Basics.min", []), do: binary_runtime_lambda("elmc_basics_min")

  def special_value_from_target("Basics.min", [left]),
    do: bound_binary_runtime_lambda("elmc_basics_min", left)

  def special_value_from_target("Basics.clamp", []),
    do: ternary_runtime_lambda("elmc_basics_clamp")

  def special_value_from_target("Basics.clamp", [low]),
    do: bound_ternary_runtime_lambda("elmc_basics_clamp", low)

  def special_value_from_target("Basics.clamp", [low, high]),
    do: bound_ternary_runtime_lambda("elmc_basics_clamp", low, high)

  def special_value_from_target("Basics.modBy", []),
    do: binary_runtime_lambda("elmc_basics_mod_by")

  def special_value_from_target("Basics.modBy", [base]),
    do: bound_binary_runtime_lambda("elmc_basics_mod_by", base)

  def special_value_from_target("Basics.remainderBy", []),
    do: binary_runtime_lambda("elmc_basics_remainder_by")

  def special_value_from_target("Basics.remainderBy", [base]),
    do: bound_binary_runtime_lambda("elmc_basics_remainder_by", base)

  def special_value_from_target("Basics.xor", []), do: binary_runtime_lambda("elmc_basics_xor")

  def special_value_from_target("Basics.xor", [a]),
    do: bound_binary_runtime_lambda("elmc_basics_xor", a)

  def special_value_from_target("Basics.compare", []),
    do: binary_runtime_lambda("elmc_basics_compare")

  def special_value_from_target("Basics.compare", [a]),
    do: bound_binary_runtime_lambda("elmc_basics_compare", a)

  def special_value_from_target("Basics.truncate", []),
    do: %{
      op: :lambda,
      args: ["__x"],
      body: %{
        op: :runtime_call,
        function: "elmc_basics_truncate",
        args: [%{op: :var, name: "__x"}]
      }
    }

  def special_value_from_target("Json.Decode.string", _args),
    do: %{op: :runtime_call, function: "elmc_json_decode_string_decoder", args: []}

  def special_value_from_target("Json.Decode.int", _args),
    do: %{op: :runtime_call, function: "elmc_json_decode_int_decoder", args: []}

  def special_value_from_target("Json.Decode.float", _args),
    do: %{op: :runtime_call, function: "elmc_json_decode_float_decoder", args: []}

  def special_value_from_target("Json.Decode.bool", _args),
    do: %{op: :runtime_call, function: "elmc_json_decode_bool_decoder", args: []}

  def special_value_from_target("Json.Decode.value", _args),
    do: %{op: :runtime_call, function: "elmc_json_decode_value_decoder", args: []}

  def special_value_from_target("Json.Encode.null", _args),
    do: %{op: :runtime_call, function: "elmc_json_encode_null", args: []}

  def special_value_from_target("Char.toCode", []),
    do: %{
      op: :lambda,
      args: ["__ch"],
      body: %{op: :runtime_call, function: "elmc_char_to_code", args: [%{op: :var, name: "__ch"}]}
    }

  def special_value_from_target("Char.fromCode", []),
    do: %{
      op: :lambda,
      args: ["__c"],
      body: %{op: :runtime_call, function: "elmc_new_char", args: [%{op: :var, name: "__c"}]}
    }

  def special_value_from_target("Debug.toString", []),
    do: %{
      op: :lambda,
      args: ["__v"],
      body: %{
        op: :runtime_call,
        function: "elmc_debug_to_string",
        args: [%{op: :var, name: "__v"}]
      }
    }

  def special_value_from_target("Debug.log", [label]),
    do: %{
      op: :lambda,
      args: ["__v"],
      body: %{
        op: :runtime_call,
        function: "elmc_debug_log",
        args: [label, %{op: :var, name: "__v"}]
      }
    }

  # --- elm/core: List ---
  def special_value_from_target("List.head", [
        %{op: :call, target: {mod, "drop"}, args: [index, list]}
      ])
      when mod in ["List"],
      do: %{op: :runtime_call, function: "elmc_list_nth_maybe", args: [list, index]}

  def special_value_from_target("List.head", [
        %{op: :qualified_call, target: target, args: [index, list]}
      ])
      when target in ["List.drop", "drop"],
      do: %{op: :runtime_call, function: "elmc_list_nth_maybe", args: [list, index]}

  def special_value_from_target("List.head", [list]),
    do: %{op: :runtime_call, function: "elmc_list_head", args: [list]}

  def special_value_from_target("List.tail", [list]),
    do: %{op: :runtime_call, function: "elmc_list_tail", args: [list]}

  def special_value_from_target("List.isEmpty", [list]),
    do: %{op: :runtime_call, function: "elmc_list_is_empty", args: [list]}

  def special_value_from_target("List.length", [list]),
    do: %{op: :runtime_call, function: "elmc_list_length", args: [list]}

  def special_value_from_target("List.reverse", [list]),
    do: %{op: :runtime_call, function: "elmc_list_reverse", args: [list]}

  def special_value_from_target("List.member", [value, list]),
    do: %{op: :runtime_call, function: "elmc_list_member", args: [value, list]}

  def special_value_from_target("List.map", [f]),
    do: %{
      op: :lambda,
      args: ["__list"],
      body: %{
        op: :runtime_call,
        function: "elmc_list_map",
        args: [f, %{op: :var, name: "__list"}]
      }
    }

  def special_value_from_target("List.map", [f, list]),
    do: %{op: :runtime_call, function: "elmc_list_map", args: [f, list]}

  def special_value_from_target("List.filter", [f]),
    do: %{
      op: :lambda,
      args: ["__list"],
      body: %{
        op: :runtime_call,
        function: "elmc_list_filter",
        args: [f, %{op: :var, name: "__list"}]
      }
    }

  def special_value_from_target("List.filter", [f, list]),
    do: %{op: :runtime_call, function: "elmc_list_filter", args: [f, list]}

  def special_value_from_target("List.foldl", [f, acc, list]),
    do: %{op: :runtime_call, function: "elmc_list_foldl", args: [f, acc, list]}

  def special_value_from_target("List.foldl", []),
    do: runtime_fn_lambda("elmc_list_foldl", ["__f", "__acc", "__list"])

  def special_value_from_target("List.foldl", [f, acc]),
    do: %{
      op: :lambda,
      args: ["__list"],
      body: %{
        op: :runtime_call,
        function: "elmc_list_foldl",
        args: [f, acc, %{op: :var, name: "__list"}]
      }
    }

  def special_value_from_target("List.foldl", [f]),
    do: %{
      op: :lambda,
      args: ["__acc", "__list"],
      body: %{
        op: :runtime_call,
        function: "elmc_list_foldl",
        args: [f, %{op: :var, name: "__acc"}, %{op: :var, name: "__list"}]
      }
    }

  def special_value_from_target("Elm.Kernel.List.foldl", []),
    do: runtime_fn_lambda("elmc_list_foldl", ["__f", "__acc", "__list"])

  def special_value_from_target("List.foldr", [f, acc, list]),
    do: %{op: :runtime_call, function: "elmc_list_foldr", args: [f, acc, list]}

  def special_value_from_target("List.foldr", []),
    do: runtime_fn_lambda("elmc_list_foldr", ["__f", "__acc", "__list"])

  def special_value_from_target("List.foldr", [f, acc]),
    do: %{
      op: :lambda,
      args: ["__list"],
      body: %{
        op: :runtime_call,
        function: "elmc_list_foldr",
        args: [f, acc, %{op: :var, name: "__list"}]
      }
    }

  def special_value_from_target("List.foldr", [f]),
    do: %{
      op: :lambda,
      args: ["__acc", "__list"],
      body: %{
        op: :runtime_call,
        function: "elmc_list_foldr",
        args: [f, %{op: :var, name: "__acc"}, %{op: :var, name: "__list"}]
      }
    }

  def special_value_from_target("List.append", [a, b]),
    do: %{op: :runtime_call, function: "elmc_list_append", args: [a, b]}

  def special_value_from_target("List.concat", [lists]),
    do: %{op: :runtime_call, function: "elmc_list_concat", args: [lists]}

  def special_value_from_target("List.concatMap", [f, list]),
    do: %{op: :runtime_call, function: "elmc_list_concat_map", args: [f, list]}

  def special_value_from_target("List.indexedMap", [f, list]),
    do: %{op: :runtime_call, function: "elmc_list_indexed_map", args: [f, list]}

  def special_value_from_target("List.filterMap", [f, list]),
    do: %{op: :runtime_call, function: "elmc_list_filter_map", args: [f, list]}

  def special_value_from_target("List.sum", [list]),
    do: %{op: :runtime_call, function: "elmc_list_sum", args: [list]}

  def special_value_from_target("List.product", [list]),
    do: %{op: :runtime_call, function: "elmc_list_product", args: [list]}

  def special_value_from_target("List.maximum", [list]),
    do: %{op: :runtime_call, function: "elmc_list_maximum", args: [list]}

  def special_value_from_target("List.minimum", [list]),
    do: %{op: :runtime_call, function: "elmc_list_minimum", args: [list]}

  def special_value_from_target("List.any", [f, list]),
    do: %{op: :runtime_call, function: "elmc_list_any", args: [f, list]}

  def special_value_from_target("List.all", [f, list]),
    do: %{op: :runtime_call, function: "elmc_list_all", args: [f, list]}

  def special_value_from_target("List.sort", [list]),
    do: %{op: :runtime_call, function: "elmc_list_sort", args: [list]}

  def special_value_from_target("List.sortBy", [f, list]),
    do: %{op: :runtime_call, function: "elmc_list_sort_by", args: [f, list]}

  def special_value_from_target("List.sortWith", [f, list]),
    do: %{op: :runtime_call, function: "elmc_list_sort_with", args: [f, list]}

  def special_value_from_target("List.singleton", [value]),
    do: %{op: :runtime_call, function: "elmc_list_singleton", args: [value]}

  def special_value_from_target("List.range", [lo, hi]),
    do: %{op: :runtime_call, function: "elmc_list_range", args: [lo, hi]}

  def special_value_from_target("List.repeat", [n, value]),
    do: %{op: :runtime_call, function: "elmc_list_repeat", args: [n, value]}

  def special_value_from_target("List.take", [n, list]),
    do: %{op: :runtime_call, function: "elmc_list_take", args: [n, list]}

  def special_value_from_target("List.drop", [n, list]),
    do: %{op: :runtime_call, function: "elmc_list_drop", args: [n, list]}

  def special_value_from_target("List.partition", [f, list]),
    do: %{op: :runtime_call, function: "elmc_list_partition", args: [f, list]}

  def special_value_from_target("List.unzip", [list]),
    do: %{op: :runtime_call, function: "elmc_list_unzip", args: [list]}

  def special_value_from_target("List.intersperse", [sep, list]),
    do: %{op: :runtime_call, function: "elmc_list_intersperse", args: [sep, list]}

  def special_value_from_target("List.map2", [f, a, b]),
    do: %{op: :runtime_call, function: "elmc_list_map2", args: [f, a, b]}

  def special_value_from_target("List.map3", [f, a, b, c]),
    do: %{op: :runtime_call, function: "elmc_list_map3", args: [f, a, b, c]}

  def special_value_from_target("List.map4", [f, a, b, c, d]),
    do: %{op: :runtime_call, function: "elmc_list_map4", args: [f, a, b, c, d]}

  def special_value_from_target("List.map5", [f, a, b, c, d, e]),
    do: %{op: :runtime_call, function: "elmc_list_map5", args: [f, a, b, c, d, e]}

  # --- elm/core: Maybe ---
  def special_value_from_target("Maybe.withDefault", [
        %{op: default_op} = default_val,
        %{
          op: :qualified_call,
          target: head_target,
          args: [
            %{
              op: :qualified_call,
              target: drop_target,
              args: [index, list]
            }
          ]
        }
      ])
      when default_op in [:int_literal, :c_int_expr, :char_literal] and
             head_target in ["List.head", "head"] and
             drop_target in ["List.drop", "drop"] do
    %{
      op: :runtime_call,
      function: "elmc_list_nth_int_default_boxed",
      args: [list, index, default_val]
    }
  end

  def special_value_from_target("Maybe.withDefault", [
        %{op: default_op} = default_val,
        %{op: :runtime_call, function: "elmc_list_nth_maybe", args: [list, index]}
      ])
      when default_op in [:int_literal, :c_int_expr, :char_literal] do
    %{
      op: :runtime_call,
      function: "elmc_list_nth_int_default_boxed",
      args: [list, index, default_val]
    }
  end

  def special_value_from_target("Maybe.withDefault", [default_val, maybe]),
    do: %{op: :runtime_call, function: "elmc_maybe_with_default", args: [default_val, maybe]}

  def special_value_from_target("Maybe.map", [f, maybe]),
    do: %{op: :runtime_call, function: "elmc_maybe_map", args: [f, maybe]}

  def special_value_from_target("Maybe.map2", [f, a, b]),
    do: %{op: :runtime_call, function: "elmc_maybe_map2", args: [f, a, b]}

  def special_value_from_target("Maybe.andThen", [f, maybe]),
    do: %{op: :runtime_call, function: "elmc_maybe_and_then", args: [f, maybe]}

  # --- elm/core: Result ---
  def special_value_from_target("Result.map", [f, result]),
    do: %{op: :runtime_call, function: "elmc_result_map", args: [f, result]}

  def special_value_from_target("Result.mapError", [f, result]),
    do: %{op: :runtime_call, function: "elmc_result_map_error", args: [f, result]}

  def special_value_from_target("Result.andThen", [f, result]),
    do: %{op: :runtime_call, function: "elmc_result_and_then", args: [f, result]}

  def special_value_from_target("Result.withDefault", [default_val, result]),
    do: %{op: :runtime_call, function: "elmc_result_with_default", args: [default_val, result]}

  def special_value_from_target("Result.toMaybe", [result]),
    do: %{op: :runtime_call, function: "elmc_result_to_maybe", args: [result]}

  def special_value_from_target("Result.fromMaybe", [err, maybe]),
    do: %{op: :runtime_call, function: "elmc_result_from_maybe", args: [err, maybe]}

  def special_value_from_target("Task.map", [f, task]),
    do: %{op: :runtime_call, function: "elmc_task_map", args: [f, task]}

  def special_value_from_target("Task.map2", [f, a, b]),
    do: %{op: :runtime_call, function: "elmc_task_map2", args: [f, a, b]}

  def special_value_from_target("Task.andThen", [f, task]),
    do: %{op: :runtime_call, function: "elmc_task_and_then", args: [f, task]}

  def special_value_from_target("Task.perform", [to_msg, task]),
    do: %{op: :runtime_call, function: "elmc_task_perform", args: [to_msg, task]}

  # --- elm/core: String (extended) ---
  def special_value_from_target("String.length", [s]),
    do: %{op: :runtime_call, function: "elmc_string_length_val", args: [s]}

  def special_value_from_target("String.reverse", [s]),
    do: %{op: :runtime_call, function: "elmc_string_reverse", args: [s]}

  def special_value_from_target("String.repeat", [n, s]),
    do: %{op: :runtime_call, function: "elmc_string_repeat", args: [n, s]}

  def special_value_from_target("String.replace", [old, new_s, s]),
    do: %{op: :runtime_call, function: "elmc_string_replace", args: [old, new_s, s]}

  def special_value_from_target("String.fromInt", [n]),
    do: %{op: :runtime_call, function: "elmc_string_from_int", args: [n]}

  def special_value_from_target("String.toInt", [s]),
    do: %{op: :runtime_call, function: "elmc_string_to_int", args: [s]}

  def special_value_from_target("String.fromFloat", [f]),
    do: %{op: :runtime_call, function: "elmc_string_from_float", args: [f]}

  def special_value_from_target("String.toFloat", [s]),
    do: %{op: :runtime_call, function: "elmc_string_to_float", args: [s]}

  def special_value_from_target("String.toUpper", [s]),
    do: %{op: :runtime_call, function: "elmc_string_to_upper", args: [s]}

  def special_value_from_target("String.toLower", [s]),
    do: %{op: :runtime_call, function: "elmc_string_to_lower", args: [s]}

  def special_value_from_target("String.trim", [s]),
    do: %{op: :runtime_call, function: "elmc_string_trim", args: [s]}

  def special_value_from_target("String.trimLeft", [s]),
    do: %{op: :runtime_call, function: "elmc_string_trim_left", args: [s]}

  def special_value_from_target("String.trimRight", [s]),
    do: %{op: :runtime_call, function: "elmc_string_trim_right", args: [s]}

  def special_value_from_target("String.contains", [sub, s]),
    do: %{op: :runtime_call, function: "elmc_string_contains", args: [sub, s]}

  def special_value_from_target("String.startsWith", [prefix, s]),
    do: %{op: :runtime_call, function: "elmc_string_starts_with", args: [prefix, s]}

  def special_value_from_target("String.endsWith", [suffix, s]),
    do: %{op: :runtime_call, function: "elmc_string_ends_with", args: [suffix, s]}

  def special_value_from_target("String.split", [sep, s]),
    do: %{op: :runtime_call, function: "elmc_string_split", args: [sep, s]}

  def special_value_from_target("String.join", [sep, list]),
    do: %{op: :runtime_call, function: "elmc_string_join", args: [sep, list]}

  def special_value_from_target("String.words", [s]),
    do: %{op: :runtime_call, function: "elmc_string_words", args: [s]}

  def special_value_from_target("String.lines", [s]),
    do: %{op: :runtime_call, function: "elmc_string_lines", args: [s]}

  def special_value_from_target("String.slice", [start, end_idx, s]),
    do: %{op: :runtime_call, function: "elmc_string_slice", args: [start, end_idx, s]}

  def special_value_from_target("String.left", [n, s]),
    do: %{op: :runtime_call, function: "elmc_string_left", args: [n, s]}

  def special_value_from_target("String.right", [n, s]),
    do: %{op: :runtime_call, function: "elmc_string_right", args: [n, s]}

  def special_value_from_target("String.dropLeft", [n, s]),
    do: %{op: :runtime_call, function: "elmc_string_drop_left", args: [n, s]}

  def special_value_from_target("String.dropRight", [n, s]),
    do: %{op: :runtime_call, function: "elmc_string_drop_right", args: [n, s]}

  def special_value_from_target("String.cons", [ch, s]),
    do: %{op: :runtime_call, function: "elmc_string_cons", args: [ch, s]}

  def special_value_from_target("String.uncons", [s]),
    do: %{op: :runtime_call, function: "elmc_string_uncons", args: [s]}

  def special_value_from_target("String.toList", [s]),
    do: %{op: :runtime_call, function: "elmc_string_to_list", args: [s]}

  def special_value_from_target("String.fromList", [list]),
    do: %{op: :runtime_call, function: "elmc_string_from_list", args: [list]}

  def special_value_from_target("String.fromChar", [ch]),
    do: %{op: :runtime_call, function: "elmc_string_from_char", args: [ch]}

  def special_value_from_target("String.pad", [n, ch, s]),
    do: %{op: :runtime_call, function: "elmc_string_pad", args: [n, ch, s]}

  def special_value_from_target("String.padLeft", [n, ch, s]),
    do: %{op: :runtime_call, function: "elmc_string_pad_left", args: [n, ch, s]}

  def special_value_from_target("String.padRight", [n, ch, s]),
    do: %{op: :runtime_call, function: "elmc_string_pad_right", args: [n, ch, s]}

  def special_value_from_target("String.map", [f, s]),
    do: %{op: :runtime_call, function: "elmc_string_map", args: [f, s]}

  def special_value_from_target("String.filter", [f, s]),
    do: %{op: :runtime_call, function: "elmc_string_filter", args: [f, s]}

  def special_value_from_target("String.foldl", [f, acc, s]),
    do: %{op: :runtime_call, function: "elmc_string_foldl", args: [f, acc, s]}

  def special_value_from_target("String.foldr", [f, acc, s]),
    do: %{op: :runtime_call, function: "elmc_string_foldr", args: [f, acc, s]}

  def special_value_from_target("String.any", [f, s]),
    do: %{op: :runtime_call, function: "elmc_string_any", args: [f, s]}

  def special_value_from_target("String.all", [f, s]),
    do: %{op: :runtime_call, function: "elmc_string_all", args: [f, s]}

  def special_value_from_target("String.indexes", [sub, s]),
    do: %{op: :runtime_call, function: "elmc_string_indexes", args: [sub, s]}

  def special_value_from_target("String.indices", [sub, s]),
    do: %{op: :runtime_call, function: "elmc_string_indexes", args: [sub, s]}

  # --- elm/core: Tuple ---
  def special_value_from_target("Tuple.first", [t]),
    do: %{op: :runtime_call, function: "elmc_tuple_first", args: [t]}

  def special_value_from_target("Tuple.second", [t]),
    do: %{op: :runtime_call, function: "elmc_tuple_second", args: [t]}

  def special_value_from_target("Tuple.first", []),
    do: runtime_fn_lambda("elmc_tuple_first", ["__t"])

  def special_value_from_target("Tuple.second", []),
    do: runtime_fn_lambda("elmc_tuple_second", ["__t"])

  def special_value_from_target("Tuple.mapFirst", [f, t]),
    do: %{op: :runtime_call, function: "elmc_tuple_map_first", args: [f, t]}

  def special_value_from_target("Tuple.mapSecond", [f, t]),
    do: %{op: :runtime_call, function: "elmc_tuple_map_second", args: [f, t]}

  def special_value_from_target("Tuple.mapBoth", [f, g, t]),
    do: %{op: :runtime_call, function: "elmc_tuple_map_both", args: [f, g, t]}

  # --- elm/core: Basics (extended) ---
  def special_value_from_target("Basics.identity", [x]), do: x

  def special_value_from_target("Basics.always", [x, _y]), do: x

  def special_value_from_target("Basics.not", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_not", args: [x]}

  def special_value_from_target("Basics.negate", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_negate", args: [x]}

  def special_value_from_target("Basics.abs", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_abs", args: [x]}

  def special_value_from_target("Basics.toFloat", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_to_float", args: [x]}

  def special_value_from_target("Basics.e", _args),
    do: %{op: :float_literal, value: 2.718281828459045}

  def special_value_from_target("Basics.pi", _args),
    do: %{op: :float_literal, value: 3.141592653589793}

  def special_value_from_target("Basics.sqrt", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_sqrt", args: [x]}

  def special_value_from_target("Basics.logBase", [base, x]),
    do: %{op: :runtime_call, function: "elmc_basics_log_base", args: [base, x]}

  def special_value_from_target("Basics.sin", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_sin", args: [x]}

  def special_value_from_target("Basics.cos", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_cos", args: [x]}

  def special_value_from_target("Basics.tan", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_tan", args: [x]}

  def special_value_from_target("Basics.acos", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_acos", args: [x]}

  def special_value_from_target("Basics.asin", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_asin", args: [x]}

  def special_value_from_target("Basics.atan", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_atan", args: [x]}

  def special_value_from_target("Basics.atan2", [y, x]),
    do: %{op: :runtime_call, function: "elmc_basics_atan2", args: [y, x]}

  def special_value_from_target("Basics.degrees", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_degrees", args: [x]}

  def special_value_from_target("Basics.radians", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_radians", args: [x]}

  def special_value_from_target("Basics.turns", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_turns", args: [x]}

  def special_value_from_target("Basics.fromPolar", [polar]),
    do: %{op: :runtime_call, function: "elmc_basics_from_polar", args: [polar]}

  def special_value_from_target("Basics.toPolar", [point]),
    do: %{op: :runtime_call, function: "elmc_basics_to_polar", args: [point]}

  def special_value_from_target("Basics.isNaN", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_is_nan", args: [x]}

  def special_value_from_target("Basics.isInfinite", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_is_infinite", args: [x]}

  def special_value_from_target("Basics.round", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_round", args: [x]}

  def special_value_from_target("Basics.floor", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_floor", args: [x]}

  def special_value_from_target("Basics.ceiling", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_ceiling", args: [x]}

  def special_value_from_target("Basics.truncate", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_truncate", args: [x]}

  def special_value_from_target("Basics.xor", [a, b]),
    do: %{op: :runtime_call, function: "elmc_basics_xor", args: [a, b]}

  def special_value_from_target("Basics.compare", [a, b]),
    do: %{op: :runtime_call, function: "elmc_basics_compare", args: [a, b]}

  # --- elm/core: Char (extended) ---
  def special_value_from_target("Char.fromCode", [code]),
    do: %{op: :runtime_call, function: "elmc_char_from_code", args: [code]}

  def special_value_from_target("Char.isUpper", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_is_upper", args: [ch]}

  def special_value_from_target("Char.isLower", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_is_lower", args: [ch]}

  def special_value_from_target("Char.isAlpha", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_is_alpha", args: [ch]}

  def special_value_from_target("Char.isAlphaNum", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_is_alpha_num", args: [ch]}

  def special_value_from_target("Char.isDigit", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_is_digit", args: [ch]}

  def special_value_from_target("Char.isOctDigit", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_is_oct_digit", args: [ch]}

  def special_value_from_target("Char.isHexDigit", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_is_hex_digit", args: [ch]}

  def special_value_from_target("Char.toUpper", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_to_upper", args: [ch]}

  def special_value_from_target("Char.toLower", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_to_lower", args: [ch]}

  def special_value_from_target("Char.toLocaleUpper", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_to_upper", args: [ch]}

  def special_value_from_target("Char.toLocaleLower", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_to_lower", args: [ch]}

  # --- elm/core: Dict (extended) ---
  def special_value_from_target("Dict.remove", [key, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_remove", args: [key, dict]}

  def special_value_from_target("Dict.isEmpty", [dict]),
    do: %{op: :runtime_call, function: "elmc_dict_is_empty", args: [dict]}

  def special_value_from_target("Dict.keys", [dict]),
    do: %{op: :runtime_call, function: "elmc_dict_keys", args: [dict]}

  def special_value_from_target("Dict.values", [dict]),
    do: %{op: :runtime_call, function: "elmc_dict_values", args: [dict]}

  def special_value_from_target("Dict.toList", [dict]),
    do: %{op: :runtime_call, function: "elmc_dict_to_list", args: [dict]}

  def special_value_from_target("Dict.map", [f, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_map", args: [f, dict]}

  def special_value_from_target("Dict.foldl", [f, acc, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_foldl", args: [f, acc, dict]}

  def special_value_from_target("Dict.foldr", [f, acc, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_foldr", args: [f, acc, dict]}

  def special_value_from_target("Dict.filter", [f, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_filter", args: [f, dict]}

  def special_value_from_target("Dict.partition", [f, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_partition", args: [f, dict]}

  def special_value_from_target("Dict.union", [a, b]),
    do: %{op: :runtime_call, function: "elmc_dict_union", args: [a, b]}

  def special_value_from_target("Dict.intersect", [a, b]),
    do: %{op: :runtime_call, function: "elmc_dict_intersect", args: [a, b]}

  def special_value_from_target("Dict.diff", [a, b]),
    do: %{op: :runtime_call, function: "elmc_dict_diff", args: [a, b]}

  def special_value_from_target("Dict.merge", [left_fn, both_fn, right_fn, a, b, result]),
    do: %{
      op: :runtime_call,
      function: "elmc_dict_merge",
      args: [left_fn, both_fn, right_fn, a, b, result]
    }

  def special_value_from_target("Dict.merge", [left_fn, both_fn, right_fn, a, b]),
    do: %{
      op: :runtime_call,
      function: "elmc_dict_merge",
      args: [left_fn, both_fn, right_fn, a, b, %{op: :list_literal, items: []}]
    }

  def special_value_from_target("Dict.update", [key, f, dict]),
    do: %{op: :runtime_call, function: "elmc_dict_update", args: [key, f, dict]}

  def special_value_from_target("Dict.singleton", [key, value]),
    do: %{op: :runtime_call, function: "elmc_dict_singleton", args: [key, value]}

  # --- elm/core: Set (extended) ---
  def special_value_from_target("Set.singleton", [value]),
    do: %{op: :runtime_call, function: "elmc_set_singleton", args: [value]}

  def special_value_from_target("Set.remove", [value, set]),
    do: %{op: :runtime_call, function: "elmc_set_remove", args: [value, set]}

  def special_value_from_target("Set.remove", []),
    do: runtime_fn_lambda("elmc_set_remove", ["__value", "__set"])

  def special_value_from_target("Set.isEmpty", [set]),
    do: %{op: :runtime_call, function: "elmc_set_is_empty", args: [set]}

  def special_value_from_target("Set.toList", [set]),
    do: %{op: :runtime_call, function: "elmc_set_to_list", args: [set]}

  def special_value_from_target("Set.union", [a, b]),
    do: %{op: :runtime_call, function: "elmc_set_union", args: [a, b]}

  def special_value_from_target("Set.intersect", [a, b]),
    do: %{op: :runtime_call, function: "elmc_set_intersect", args: [a, b]}

  def special_value_from_target("Set.diff", [a, b]),
    do: %{op: :runtime_call, function: "elmc_set_diff", args: [a, b]}

  def special_value_from_target("Set.map", [f, set]),
    do: %{op: :runtime_call, function: "elmc_set_map", args: [f, set]}

  def special_value_from_target("Set.foldl", [f, acc, set]),
    do: %{op: :runtime_call, function: "elmc_set_foldl", args: [f, acc, set]}

  def special_value_from_target("Set.foldr", [f, acc, set]),
    do: %{op: :runtime_call, function: "elmc_set_foldr", args: [f, acc, set]}

  def special_value_from_target("Set.filter", [f, set]),
    do: %{op: :runtime_call, function: "elmc_set_filter", args: [f, set]}

  def special_value_from_target("Set.partition", [f, set]),
    do: %{op: :runtime_call, function: "elmc_set_partition", args: [f, set]}

  # --- elm/core: Array (extended) ---
  def special_value_from_target("Array.initialize", [n, f]),
    do: %{op: :runtime_call, function: "elmc_array_initialize", args: [n, f]}

  def special_value_from_target("Array.repeat", [n, value]),
    do: %{op: :runtime_call, function: "elmc_array_repeat", args: [n, value]}

  def special_value_from_target("Array.isEmpty", [array]),
    do: %{op: :runtime_call, function: "elmc_array_is_empty", args: [array]}

  def special_value_from_target("Array.toList", [array]),
    do: %{op: :runtime_call, function: "elmc_array_to_list", args: [array]}

  def special_value_from_target("Array.toIndexedList", [array]),
    do: %{op: :runtime_call, function: "elmc_array_to_indexed_list", args: [array]}

  def special_value_from_target("Array.map", [f, array]),
    do: %{op: :runtime_call, function: "elmc_array_map", args: [f, array]}

  def special_value_from_target("Array.indexedMap", [f, array]),
    do: %{op: :runtime_call, function: "elmc_array_indexed_map", args: [f, array]}

  def special_value_from_target("Array.foldl", [f, acc, array]),
    do: %{op: :runtime_call, function: "elmc_array_foldl", args: [f, acc, array]}

  def special_value_from_target("Array.foldr", [f, acc, array]),
    do: %{op: :runtime_call, function: "elmc_array_foldr", args: [f, acc, array]}

  def special_value_from_target("Array.filter", [f, array]),
    do: %{op: :runtime_call, function: "elmc_array_filter", args: [f, array]}

  def special_value_from_target("Array.append", [a, b]),
    do: %{op: :runtime_call, function: "elmc_array_append", args: [a, b]}

  def special_value_from_target("Array.slice", [start, end_idx, array]),
    do: %{op: :runtime_call, function: "elmc_array_slice", args: [start, end_idx, array]}

  # --- elm/json: Json.Decode ---
  def special_value_from_target("Json.Decode.decodeValue", [decoder, value]),
    do: %{op: :runtime_call, function: "elmc_json_decode_value", args: [decoder, value]}

  def special_value_from_target("Json.Decode.decodeString", [decoder, s]),
    do: %{op: :runtime_call, function: "elmc_json_decode_string", args: [decoder, s]}

  def special_value_from_target("Json.Decode.null", [default_val]),
    do: %{op: :runtime_call, function: "elmc_json_decode_null", args: [default_val]}

  def special_value_from_target("Json.Decode.nullable", [decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_nullable", args: [decoder]}

  def special_value_from_target("Json.Decode.list", [decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_list", args: [decoder]}

  def special_value_from_target("Json.Decode.array", [decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_array", args: [decoder]}

  def special_value_from_target("Json.Decode.field", [name, decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_field", args: [name, decoder]}

  def special_value_from_target("Json.Decode.at", [path, decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_at", args: [path, decoder]}

  def special_value_from_target("Json.Decode.index", [idx, decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_index", args: [idx, decoder]}

  def special_value_from_target("Json.Decode.map", [f, decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_map", args: [f, decoder]}

  def special_value_from_target("Json.Decode.map2", [f, d1, d2]),
    do: %{op: :runtime_call, function: "elmc_json_decode_map2", args: [f, d1, d2]}

  def special_value_from_target("Json.Decode.map3", [f, d1, d2, d3]),
    do: %{op: :runtime_call, function: "elmc_json_decode_map3", args: [f, d1, d2, d3]}

  def special_value_from_target("Json.Decode.map4", [f, d1, d2, d3, d4]),
    do: %{op: :runtime_call, function: "elmc_json_decode_map4", args: [f, d1, d2, d3, d4]}

  def special_value_from_target("Json.Decode.map5", [f, d1, d2, d3, d4, d5]),
    do: %{op: :runtime_call, function: "elmc_json_decode_map5", args: [f, d1, d2, d3, d4, d5]}

  def special_value_from_target("Json.Decode.map6", [f, d1, d2, d3, d4, d5, d6]),
    do: %{op: :runtime_call, function: "elmc_json_decode_map6", args: [f, d1, d2, d3, d4, d5, d6]}

  def special_value_from_target("Json.Decode.map7", [f, d1, d2, d3, d4, d5, d6, d7]),
    do: %{
      op: :runtime_call,
      function: "elmc_json_decode_map7",
      args: [f, d1, d2, d3, d4, d5, d6, d7]
    }

  def special_value_from_target("Json.Decode.succeed", [value]),
    do: %{op: :runtime_call, function: "elmc_json_decode_succeed", args: [value]}

  def special_value_from_target("Json.Decode.fail", [msg]),
    do: %{op: :runtime_call, function: "elmc_json_decode_fail", args: [msg]}

  def special_value_from_target("Json.Decode.andThen", [f, decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_and_then", args: [f, decoder]}

  def special_value_from_target("Json.Decode.oneOf", [decoders]),
    do: %{op: :runtime_call, function: "elmc_json_decode_one_of", args: [decoders]}

  def special_value_from_target("Json.Decode.maybe", [decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_maybe", args: [decoder]}

  def special_value_from_target("Json.Decode.lazy", [thunk]),
    do: %{op: :runtime_call, function: "elmc_json_decode_lazy", args: [thunk]}

  def special_value_from_target("Json.Decode.errorToString", [err]),
    do: %{op: :runtime_call, function: "elmc_json_decode_error_to_string", args: [err]}

  def special_value_from_target("Json.Decode.errorToString", []),
    do: %{
      op: :lambda,
      args: ["__err"],
      body: %{
        op: :runtime_call,
        function: "elmc_json_decode_error_to_string",
        args: [%{op: :var, name: "__err"}]
      }
    }

  def special_value_from_target("Json.Decode.keyValuePairs", [decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_key_value_pairs", args: [decoder]}

  def special_value_from_target("Json.Decode.dict", [decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_dict", args: [decoder]}

  # --- elm/json: Json.Encode ---
  def special_value_from_target("Json.Encode.string", [s]),
    do: %{op: :runtime_call, function: "elmc_json_encode_string", args: [s]}

  def special_value_from_target("Json.Encode.string", []),
    do: runtime_fn_lambda("elmc_json_encode_string", ["__s"])

  def special_value_from_target("Json.Encode.int", [n]),
    do: %{op: :runtime_call, function: "elmc_json_encode_int", args: [n]}

  def special_value_from_target("Json.Encode.int", []),
    do: runtime_fn_lambda("elmc_json_encode_int", ["__n"])

  def special_value_from_target("Json.Encode.float", [f]),
    do: %{op: :runtime_call, function: "elmc_json_encode_float", args: [f]}

  def special_value_from_target("Json.Encode.float", []),
    do: runtime_fn_lambda("elmc_json_encode_float", ["__f"])

  def special_value_from_target("Json.Encode.bool", [b]),
    do: %{op: :runtime_call, function: "elmc_json_encode_bool", args: [b]}

  def special_value_from_target("Json.Encode.bool", []),
    do: runtime_fn_lambda("elmc_json_encode_bool", ["__b"])

  def special_value_from_target("Json.Encode.list", [f, items]),
    do: %{op: :runtime_call, function: "elmc_json_encode_list", args: [f, items]}

  def special_value_from_target("Json.Encode.list", [_f]),
    do: runtime_fn_lambda("elmc_json_encode_list", ["__f", "__items"])

  def special_value_from_target("Json.Encode.array", [f, items]),
    do: %{op: :runtime_call, function: "elmc_json_encode_array", args: [f, items]}

  def special_value_from_target("Json.Encode.array", [_f]),
    do: runtime_fn_lambda("elmc_json_encode_array", ["__f", "__items"])

  def special_value_from_target("Json.Encode.set", [f, items]),
    do: %{op: :runtime_call, function: "elmc_json_encode_set", args: [f, items]}

  def special_value_from_target("Json.Encode.object", [pairs]),
    do: %{op: :runtime_call, function: "elmc_json_encode_object", args: [pairs]}

  def special_value_from_target("Json.Encode.dict", [key_fn, val_fn, dict]),
    do: %{op: :runtime_call, function: "elmc_json_encode_dict", args: [key_fn, val_fn, dict]}

  def special_value_from_target("Json.Encode.encode", [indent, value]),
    do: %{op: :runtime_call, function: "elmc_json_encode_encode", args: [indent, value]}

  def special_value_from_target(target, []) when is_binary(target) do
    cond do
      target in ["True", "Basics.True"] or String.ends_with?(target, ".True") ->
        %{op: :bool_literal, value: true}

      target in ["False", "Basics.False"] or String.ends_with?(target, ".False") ->
        %{op: :bool_literal, value: false}

      target in ["LT", "Basics.LT"] or String.ends_with?(target, ".LT") ->
        %{op: :order_literal, value: -1}

      target in ["EQ", "Basics.EQ"] or String.ends_with?(target, ".EQ") ->
        %{op: :order_literal, value: 0}

      target in ["GT", "Basics.GT"] or String.ends_with?(target, ".GT") ->
        %{op: :order_literal, value: 1}

      target in ["Basics.e"] ->
        %{op: :float_literal, value: 2.718281828459045}

      target in ["Basics.pi"] ->
        %{op: :float_literal, value: 3.141592653589793}

      target == "()" ->
        %{op: :runtime_call, function: "elmc_unit", args: []}

      Map.has_key?(IRQueries.bundled_union_constructor_tags(), target) ->
        %{op: :int_literal, value: Map.fetch!(IRQueries.bundled_union_constructor_tags(), target)}

      true ->
        nil
    end
  end

  def special_value_from_target(target, nil) when is_binary(target),
    do: special_value_from_target(target, [])

  def special_value_from_target(target, args) when is_binary(target) and is_list(args) do
    normalized = normalize_special_target(target)
    if normalized == target, do: nil, else: special_value_from_target(normalized, args)
  end

  def special_value_from_target(_, _), do: nil

  @spec normalize_special_target(String.t()) :: String.t()
  def normalize_special_target(target) when is_binary(target) do
    normalize_bare_special_target(target)
  end

  @spec normalize_bare_special_target(String.t()) :: String.t()
  defp normalize_bare_special_target(target) when is_binary(target) do
    case target do
      "Clear" -> "Pebble.Ui.clear"
      "Pixel" -> "Pebble.Ui.pixel"
      "Line" -> "Pebble.Ui.line"
      "RectOp" -> "Pebble.Ui.rect"
      "FillRect" -> "Pebble.Ui.fillRect"
      "Circle" -> "Pebble.Ui.circle"
      "FillCircle" -> "Pebble.Ui.fillCircle"
      "TextInt" -> "Pebble.Ui.textInt"
      "TextLabel" -> "Pebble.Ui.textLabel"
      "Text" -> "Pebble.Ui.text"
      "StrokeWidth" -> "Pebble.Ui.strokeWidth"
      "Antialiased" -> "Pebble.Ui.antialiased"
      "StrokeColor" -> "Pebble.Ui.strokeColor"
      "FillColor" -> "Pebble.Ui.fillColor"
      "TextColor" -> "Pebble.Ui.textColor"
      "CompositingMode" -> "Pebble.Ui.compositingMode"
      "Group" -> "Pebble.Ui.group"
      "PathFilled" -> "Pebble.Ui.pathFilled"
      "PathOutline" -> "Pebble.Ui.pathOutline"
      "PathOutlineOpen" -> "Pebble.Ui.pathOutlineOpen"
      "RoundRect" -> "Pebble.Ui.roundRect"
      "Arc" -> "Pebble.Ui.arc"
      "FillRadial" -> "Pebble.Ui.fillRadial"
      "BitmapInRect" -> "Pebble.Ui.drawBitmapInRect"
      "RotatedBitmap" -> "Pebble.Ui.drawRotatedBitmap"
      "VectorAt" -> "Pebble.Ui.drawVectorAt"
      "VectorSequenceAt" -> "Pebble.Ui.drawVectorSequenceAt"
      "BitmapSequenceAt" -> "Pebble.Ui.drawBitmapSequenceAt"
      other -> other
    end
  end

  @spec encoded_cmd_expr(non_neg_integer(), [map()], non_neg_integer()) :: map()
  defp encoded_cmd_expr(kind, args, arity) do
    if length(args) == arity do
      if pebble_cmd_eligible?(args) do
        %{op: :pebble_cmd, kind: command_kind_expr(kind), params: args}
      else
        encoded_cmd_as_tuple(command_kind_expr(kind), args)
      end
    else
      %{op: :unsupported}
    end
  end

  # Draw op ids overlap runtime command ids (e.g. fill_circle and get_clock_style_24h are
  # both 8). Field-expanded draw args must always encode as render-op tuples, never
  # :pebble_cmd with command_kind_expr/1.
  @spec encoded_draw_field_cmd_expr(non_neg_integer(), [map()], non_neg_integer()) :: map()
  defp encoded_draw_field_cmd_expr(kind, args, arity) do
    if length(args) == arity do
      encoded_cmd_as_tuple(draw_kind_expr(kind), args)
    else
      %{op: :unsupported}
    end
  end

  @spec encoded_cmd_as_tuple(map(), [map()]) :: map()
  def encoded_cmd_as_tuple(kind_expr, args) when is_list(args) do
    arity = length(args)
    payload = args ++ List.duplicate(%{op: :int_literal, value: 0}, max(0, 6 - arity))
    %{op: :tuple2, left: kind_expr, right: tuple_chain(payload)}
  end

  defp pebble_cmd_eligible?(args) do
    length(args) <= 5 and Enum.all?(args, &pebble_cmd_param?/1)
  end

  defp pebble_cmd_param?(%{op: op}) when op in [:int_literal, :c_int_expr, :msg_tag_expr],
    do: true

  defp pebble_cmd_param?(%{op: :var}), do: true
  defp pebble_cmd_param?(%{op: :call}), do: true
  defp pebble_cmd_param?(%{op: :runtime_call}), do: true
  defp pebble_cmd_param?(%{op: :field_access}), do: true
  defp pebble_cmd_param?(%{op: :if}), do: true
  defp pebble_cmd_param?(%{op: :case}), do: true
  defp pebble_cmd_param?(%{op: :let_in}), do: true
  defp pebble_cmd_param?(%{op: :compare}), do: true
  defp pebble_cmd_param?(%{op: :add_const}), do: true
  defp pebble_cmd_param?(%{op: :add_vars}), do: true
  defp pebble_cmd_param?(%{op: :sub_const}), do: true

  defp pebble_cmd_param?(%{op: :constructor_call, args: args}) when is_list(args),
    do: Enum.all?(args, &pebble_cmd_param?/1)

  defp pebble_cmd_param?(%{op: :qualified_call, args: args}) when is_list(args),
    do: Enum.all?(args, &pebble_cmd_param?/1)

  defp pebble_cmd_param?(_), do: false

  @spec encoded_draw_cmd_expr(non_neg_integer(), [Types.ir_expr()], non_neg_integer()) ::
          Types.ir_expr()
  defp encoded_draw_cmd_expr(kind, args, arity) do
    if length(args) == arity do
      payload = args ++ List.duplicate(%{op: :int_literal, value: 0}, max(0, 6 - arity))
      %{op: :tuple2, left: draw_kind_expr(kind), right: tuple_chain(payload)}
    else
      %{op: :unsupported}
    end
  end

  @spec encoded_text_cmd_expr(non_neg_integer(), [Types.ir_expr()]) :: Types.ir_expr()
  defp encoded_text_cmd_expr(kind, args) when is_list(args) and length(args) >= 2 do
    {value, payload} = List.pop_at(args, -1)
    %{op: :tuple2, left: draw_kind_expr(kind), right: tuple_chain(payload ++ [value])}
  end

  defp encoded_text_cmd_expr(_kind, _args), do: %{op: :unsupported}

  defp text_alignment_expr(:left), do: %{op: :c_int_expr, value: "ELMC_TEXT_ALIGN_LEFT"}
  defp text_alignment_expr(:center), do: %{op: :c_int_expr, value: "ELMC_TEXT_ALIGN_CENTER"}
  defp text_alignment_expr(:right), do: %{op: :c_int_expr, value: "ELMC_TEXT_ALIGN_RIGHT"}

  defp text_overflow_expr(:word_wrap),
    do: %{op: :c_int_expr, value: "ELMC_TEXT_OVERFLOW_WORD_WRAP"}

  defp text_overflow_expr(:trailing_ellipsis),
    do: %{op: :c_int_expr, value: "ELMC_TEXT_OVERFLOW_TRAILING_ELLIPSIS"}

  defp text_overflow_expr(:fill), do: %{op: :c_int_expr, value: "ELMC_TEXT_OVERFLOW_FILL"}

  @spec tuple_chain([Types.ir_expr()]) :: Types.ir_expr()
  defp tuple_chain([single]), do: single

  defp tuple_chain([head | rest]) do
    %{op: :tuple2, left: head, right: tuple_chain(rest)}
  end

  defp health_metric_to_kernel_expr(%{op: :constructor_call, target: target, args: []})
       when is_binary(target) do
    %{
      op: :int_literal,
      value: Map.get(IRQueries.bundled_health_metric_kernel_values(), target, 0)
    }
  end

  defp health_metric_to_kernel_expr(%{op: :int_literal, value: value}) when is_integer(value),
    do: %{op: :int_literal, value: value}

  defp health_metric_to_kernel_expr(metric) when is_map(metric), do: metric

  defp runtime_fn_lambda(function, arg_names) when is_binary(function) and is_list(arg_names) do
    %{
      op: :lambda,
      args: arg_names,
      body: %{
        op: :runtime_call,
        function: function,
        args: Enum.map(arg_names, &%{op: :var, name: &1})
      }
    }
  end

  @spec http_request_constructor_expr(String.t(), Types.ir_expr(), Types.ir_expr()) ::
          Types.ir_expr()
  defp http_request_constructor_expr(method_ctor, url, to_msg) do
    method = %{op: :constructor_call, target: "Pebble.Http.#{method_ctor}", args: []}

    req =
      %{
        op: :record_literal,
        fields: [
          {"method", method},
          {"url", url},
          {"headers", %{op: :list_literal, items: []}},
          {"body", %{op: :constructor_call, target: "Nothing", args: []}},
          {"timeout", %{op: :constructor_call, target: "Nothing", args: []}}
        ]
      }

    %{op: :constructor_call, target: "Pebble.Http.Request", args: [req, to_msg]}
  end

  @spec constructor_tag_expr(map()) :: map()
  defp constructor_tag_expr(%{op: :int_literal, union_ctor: ctor}) when is_binary(ctor) do
    msg_tag_expr(ctor)
  end

  defp constructor_tag_expr(%{op: :int_literal, value: value}) when is_integer(value) do
    %{op: :int_literal, value: value}
  end

  defp constructor_tag_expr(%{op: :var, name: name}) when is_binary(name) do
    if msg_constructor_name?(name), do: msg_tag_expr(name), else: %{op: :int_literal, value: 0}
  end

  defp constructor_tag_expr(%{op: :qualified_ref, target: target}) when is_binary(target) do
    if msg_constructor_name?(target),
      do: msg_tag_expr(target),
      else: %{op: :int_literal, value: 0}
  end

  defp constructor_tag_expr(%{op: :qualified_var, target: target}) when is_binary(target) do
    if msg_constructor_name?(target),
      do: msg_tag_expr(target),
      else: %{op: :int_literal, value: 0}
  end

  defp constructor_tag_expr(%{op: :constructor_call, target: target, args: []})
       when is_binary(target) do
    if msg_constructor_name?(target),
      do: msg_tag_expr(target),
      else: %{op: :int_literal, value: 0}
  end

  defp constructor_tag_expr(%{op: :qualified_call, target: target, args: []})
       when is_binary(target) do
    if msg_constructor_name?(target),
      do: msg_tag_expr(target),
      else: %{op: :int_literal, value: 0}
  end

  defp constructor_tag_expr(%{op: :partial_constructor, target: target, args: []})
       when is_binary(target) do
    if msg_constructor_name?(target),
      do: msg_tag_expr(target),
      else: %{op: :int_literal, value: 0}
  end

  defp constructor_tag_expr(_), do: %{op: :int_literal, value: 0}

  defp msg_constructor_name?(name) when is_binary(name) do
    short = constructor_short_name(name)
    PebbleMsgTag.msg_constructor?(short) or PebbleMsgTag.msg_constructor?(name)
  end

  defp msg_tag_expr(name) when is_binary(name) do
    %{op: :msg_tag_expr, name: constructor_short_name(name)}
  end

  defp constructor_short_name(name) do
    name |> String.split(".") |> List.last()
  end

  @spec constructor_tag(String.t()) :: non_neg_integer()
  def constructor_tag(name) do
    tags = Process.get(:elmc_constructor_tags, %{})

    Map.get_lazy(tags, name, fn ->
      name
      |> String.split(".")
      |> List.last()
      |> then(&Map.get(tags, &1, 0))
    end)
  end

  @spec field_access_expr(Types.ir_expr(), String.t()) :: Types.ir_expr()
  def field_access_expr(arg_expr, field) when is_map(arg_expr) and is_binary(field) do
    %{op: :field_access, arg: arg_expr, field: field}
  end

  @spec text_options_update_expr(Types.ir_expr(), String.t(), Types.ir_expr()) ::
          Types.ir_expr()
  defp text_options_update_expr(options, field, value)
       when is_map(options) and is_binary(field) and is_map(value) do
    %{
      op: :record_update,
      base: options,
      fields: [%{name: field, expr: value}]
    }
  end

  defp text_options_update_expr(_options, _field, _value), do: %{op: :unsupported}

  @spec platform_union_is_constructor(Types.ir_expr(), String.t(), non_neg_integer(), String.t()) ::
          Types.ir_expr()
  defp platform_union_is_constructor(shape, name, tag, platform_static_macro)
       when is_map(shape) and is_binary(name) and is_integer(tag) and is_binary(platform_static_macro) do
    %{
      op: :case,
      subject: shape,
      branches: [
        %{
          pattern: %{kind: :constructor, name: name, tag: tag, arg_pattern: nil},
          expr: %{op: :int_literal, value: 1}
        },
        %{
          pattern: %{kind: :wildcard},
          expr: %{op: :int_literal, value: 0}
        }
      ]
    }
    |> maybe_put_platform_static_macro(platform_static_macro)
  end

  defp maybe_put_platform_static_macro(expr, macro) when is_binary(macro),
    do: Map.put(expr, :platform_static_macro, macro)

  @spec tagged_value_expr(Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()
  defp tagged_value_expr(tag, value_expr) when is_map(tag) and is_map(value_expr) do
    %{op: :tuple2, left: tag, right: value_expr}
  end

  @spec rotation_expr(Types.ir_expr()) :: Types.ir_expr()
  defp rotation_expr(angle_expr) when is_map(angle_expr) do
    tagged_value_expr(
      %{op: :int_literal, value: 1, union_ctor: "Pebble.Ui.Rotation"},
      angle_expr
    )
  end

  @spec compiler_folded_union_constructors() :: MapSet.t(String.t())
  def compiler_folded_union_constructors do
    MapSet.new(["Pebble.Ui.Rotation"])
  end

  @spec pebble_angle_expr(Types.ir_expr()) :: Types.ir_expr()
  def pebble_angle_expr(rotation) when is_map(rotation) do
    rotation =
      case rotation do
        %{op: :qualified_call, target: target, args: args} ->
          case special_value_from_target(target, args) do
            nil -> rotation
            folded -> folded
          end

        _ ->
          rotation
      end

    case compile_time_pebble_angle_expr(rotation) do
      {:ok, expr} -> expr
      :error -> rotation_to_pebble_angle_call(rotation)
    end
  end

  @spec compile_time_pebble_angle_expr(Types.ir_expr()) :: {:ok, Types.ir_expr()} | :error
  defp compile_time_pebble_angle_expr(%{op: :tuple2, left: left, right: right}) do
    if rotation_union_payload?(left), do: {:ok, right}, else: :error
  end

  defp compile_time_pebble_angle_expr(_rotation), do: :error

  @spec pebble_angle_from_degrees(number()) :: integer()
  defp pebble_angle_from_degrees(degrees), do: round(degrees * 65_536 / 360)

  defp rotation_to_pebble_angle_call(rotation) do
    %{op: :qualified_call, target: "Pebble.Ui.rotationToPebbleAngle", args: [rotation]}
  end

  defp rotation_union_payload?(%{op: :c_int_expr, value: "ELMC_UNION_ROTATION"}), do: true

  defp rotation_union_payload?(%{op: :int_literal, union_ctor: ctor}) when is_binary(ctor) do
    ctor
    |> String.split(".")
    |> List.last()
    |> Kernel.==("Rotation")
  end

  defp rotation_union_payload?(_left), do: false

  @spec path_expr(Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr()) ::
          Types.ir_expr()
  defp path_expr(points, offset_x, offset_y, rotation) do
    %{
      op: :tuple2,
      left: points,
      right: %{
        op: :tuple2,
        left: offset_x,
        right: %{
          op: :tuple2,
          left: offset_y,
          right: pebble_angle_expr(rotation)
        }
      }
    }
  end

  defp unary_runtime_lambda(function) do
    %{
      op: :lambda,
      args: ["__x"],
      body: %{op: :runtime_call, function: function, args: [%{op: :var, name: "__x"}]}
    }
  end

  defp binary_runtime_lambda(function) do
    %{
      op: :lambda,
      args: ["__a", "__b"],
      body: %{
        op: :runtime_call,
        function: function,
        args: [%{op: :var, name: "__a"}, %{op: :var, name: "__b"}]
      }
    }
  end

  defp bound_binary_runtime_lambda(function, first) do
    %{
      op: :lambda,
      args: ["__b"],
      body: %{
        op: :runtime_call,
        function: function,
        args: [first, %{op: :var, name: "__b"}]
      }
    }
  end

  defp ternary_runtime_lambda(function) do
    %{
      op: :lambda,
      args: ["__a", "__b", "__c"],
      body: %{
        op: :runtime_call,
        function: function,
        args: [
          %{op: :var, name: "__a"},
          %{op: :var, name: "__b"},
          %{op: :var, name: "__c"}
        ]
      }
    }
  end

  defp bound_ternary_runtime_lambda(function, first) do
    %{
      op: :lambda,
      args: ["__b", "__c"],
      body: %{
        op: :runtime_call,
        function: function,
        args: [first, %{op: :var, name: "__b"}, %{op: :var, name: "__c"}]
      }
    }
  end

  defp bound_ternary_runtime_lambda(function, first, second) do
    %{
      op: :lambda,
      args: ["__c"],
      body: %{
        op: :runtime_call,
        function: function,
        args: [first, second, %{op: :var, name: "__c"}]
      }
    }
  end
end
