defmodule Elmx.Runtime.ViewShape.Coerce do
  @moduledoc false

  alias Elmx.Runtime.Pebble.Ui, as: PebbleUi
  alias Elmx.Runtime.ViewShape
  alias Elmx.Runtime.ViewShape.Geometry

  def coerce_ctor("WindowStack", windows) when is_list(windows),
    do: PebbleUi.window_stack(windows)
  def coerce_ctor("WindowNode", [id, layers]), do: PebbleUi.window(id, layers)
  def coerce_ctor("CanvasLayer", [id, ops]), do: PebbleUi.canvas_layer(id, ops)
  def coerce_ctor("Group", [ctx]), do: PebbleUi.group(coerce_group_context(ctx))

  def coerce_ctor("Context", [settings, commands])
       when is_list(settings) and is_list(commands) do
    PebbleUi.context(
      Enum.map(settings, &ViewShape.coerce/1),
      Enum.map(commands, &ViewShape.coerce/1)
    )
  end

  def coerce_ctor("StrokeWidth", [v]), do: PebbleUi.context_setting("strokeWidth", v)
  def coerce_ctor("StrokeColor", [v]), do: PebbleUi.context_setting("strokeColor", v)
  def coerce_ctor("FillColor", [v]), do: PebbleUi.context_setting("fillColor", v)
  def coerce_ctor("TextColor", [v]), do: PebbleUi.context_setting("textColor", v)
  def coerce_ctor("Antialiased", [v]), do: PebbleUi.context_setting("antialiased", v)
  def coerce_ctor("CompositingMode", [v]), do: PebbleUi.context_setting("compositingMode", v)

  def coerce_ctor("Clear", [color]), do: PebbleUi.clear(color)
  def coerce_ctor("FillRect", [bounds, color]), do: PebbleUi.fill_rect(bounds, color)
  def coerce_ctor("FillRect", [x, y, w, h, color]) when is_integer(x),
    do: PebbleUi.fill_rect(Geometry.rect_map(x, y, w, h), color)

  def coerce_ctor("TextInt", [font, x, y, value]), do: PebbleUi.text_int(font, {x, y}, value)
  def coerce_ctor("TextLabel", [font, x, y, label]), do: PebbleUi.text_label(font, {x, y}, label)
  def coerce_ctor("Circle", [center, radius, color]), do: PebbleUi.circle(center, radius, color)
  def coerce_ctor("Circle", [center, radius]), do: PebbleUi.circle(center, radius)
  def coerce_ctor("Circle", [cx, cy, r, color]) when is_integer(cx),
    do: PebbleUi.circle(%{x: cx, y: cy}, r, color)

  def coerce_ctor("Line", [from, to, color]), do: PebbleUi.line(from, to, color)
  def coerce_ctor("Line", [x1, y1, x2, y2, color]) when is_integer(x1),
    do: PebbleUi.line(%{x: x1, y: y1}, %{x: x2, y: y2}, color)

  def coerce_ctor("RectOp", [bounds, color]), do: PebbleUi.rect(bounds, color)
  def coerce_ctor("RectOp", [x, y, w, h, color]) when is_integer(x),
    do: PebbleUi.rect(Geometry.rect_map(x, y, w, h), color)

  def coerce_ctor("Rect", [bounds, color]), do: PebbleUi.rect(bounds, color)
  def coerce_ctor("FillCircle", [center, radius, color]),
    do: PebbleUi.fill_circle(center, radius, color)

  def coerce_ctor("FillCircle", [center, color]), do: PebbleUi.fill_circle(center, 0, color)
  def coerce_ctor("FillCircle", [cx, cy, r, color]) when is_integer(cx),
    do: PebbleUi.fill_circle(%{x: cx, y: cy}, r, color)

  def coerce_ctor("FillRadial", [bounds, start_angle, end_angle]),
    do: PebbleUi.fill_radial(bounds, start_angle, end_angle)

  def coerce_ctor("FillRadial", [x, y, w, h, start_angle, end_angle]) when is_integer(x),
    do: PebbleUi.fill_radial(Geometry.rect_map(x, y, w, h), start_angle, end_angle)

  def coerce_ctor("RoundRect", [bounds, radius, color]),
    do: PebbleUi.round_rect(bounds, radius, color)

  def coerce_ctor("RoundRect", [x, y, w, h, radius, color]) when is_integer(x),
    do: PebbleUi.round_rect(Geometry.rect_map(x, y, w, h), radius, color)

  def coerce_ctor("Arc", [bounds, start, finish]), do: PebbleUi.arc(bounds, start, finish)
  def coerce_ctor("Arc", [x, y, w, h, start, finish]) when is_integer(x),
    do: PebbleUi.arc(Geometry.rect_map(x, y, w, h), start, finish)

  def coerce_ctor("DrawBitmapInRect", [resource, bounds]), do: PebbleUi.draw_bitmap_in_rect(resource, bounds)

  def coerce_ctor("BitmapInRect", [resource, x, y, w, h]) when is_integer(x),
    do: PebbleUi.draw_bitmap_in_rect(resource, Geometry.rect_map(x, y, w, h))

  def coerce_ctor("DrawBitmapSequenceAt", [animation_id, resource, origin]),
    do: PebbleUi.draw_bitmap_sequence_at(animation_id, resource, Geometry.coerce_point_map(origin))

  def coerce_ctor("BitmapSequenceAt", [animation_id, resource, x, y]) when is_integer(x),
    do: PebbleUi.draw_bitmap_sequence_at(animation_id, resource, %{x: x, y: y})

  def coerce_ctor("DrawRotatedBitmap", [resource, bounds, rotation, center]),
    do: PebbleUi.draw_rotated_bitmap(resource, Geometry.coerce_rect_map(bounds), rotation, Geometry.coerce_point_map(center))

  def coerce_ctor("RotatedBitmap", [resource, src_w, src_h, angle, center_x, center_y])
       when is_integer(src_w),
       do:
         PebbleUi.draw_rotated_bitmap(
           resource,
           %{x: 0, y: 0, w: src_w, h: src_h},
           angle,
           %{x: center_x, y: center_y}
         )

  def coerce_ctor("Pixel", [pos, color]), do: PebbleUi.pixel(pos, color)
  def coerce_ctor("Pixel", [x, y, color]) when is_integer(x), do: PebbleUi.pixel(%{x: x, y: y}, color)
  def coerce_ctor("DrawVectorAt", [resource, frame, origin, rotation]),
    do: PebbleUi.draw_vector_at(resource, frame, origin, rotation)

  def coerce_ctor("DrawVectorAt", [resource, origin]),
    do: PebbleUi.draw_vector_at(resource, origin)

  def coerce_ctor("DrawVectorSequenceAt", [animation_id, resource, frame, origin, rotation]),
    do: PebbleUi.draw_vector_sequence_at(animation_id, resource, frame, origin, rotation)

  def coerce_ctor("DrawVectorSequenceAt", [animation_id, resource, origin]),
    do: PebbleUi.draw_vector_sequence_at(animation_id, resource, origin)

  def coerce_ctor("Text", [font, options, bounds, value]),
    do: PebbleUi.text(font, options, bounds, value)

  def coerce_ctor("Path", [points, origin, rotation]),
    do: PebbleUi.path(Geometry.coerce_path_points(points), Geometry.coerce_point_map(origin), Geometry.coerce_rotation(rotation))

  def coerce_ctor("PathFilled", [path]), do: PebbleUi.path_filled(Geometry.coerce_path_value(path))
  def coerce_ctor("PathOutline", [path]), do: PebbleUi.path_outline(Geometry.coerce_path_value(path))
  def coerce_ctor("PathOutlineOpen", [path]), do: PebbleUi.path_outline_open(Geometry.coerce_path_value(path))

  def coerce_ctor(_other, _args), do: nil
  def coerce_group_context({settings, commands}) when is_list(settings) and is_list(commands) do
    %{style: coerce_context_settings(settings), ops: commands}
  end

  def coerce_group_context(%{"ctor" => "Context", "args" => [{settings, commands}]}) do
    coerce_group_context({settings, commands})
  end

  def coerce_group_context(%{settings: settings, ops: ops}) when is_list(ops) do
    %{style: coerce_context_settings(settings), ops: ops}
  end

  def coerce_group_context(other), do: other

  def coerce_context_settings(settings) when is_list(settings) do
    Enum.reduce(settings, %{}, fn setting, acc ->
      case setting do
        %{"ctor" => "StrokeWidth", "args" => [v]} -> Map.put(acc, "stroke_width", v)
        %{"ctor" => "Antialiased", "args" => [v]} -> Map.put(acc, "antialiased", v)
        %{"ctor" => "StrokeColor", "args" => [v]} ->
          Map.put(acc, "stroke_color", Elmx.Runtime.Pebble.Colors.to_int(v))

        %{"ctor" => "FillColor", "args" => [v]} ->
          Map.put(acc, "fill_color", Elmx.Runtime.Pebble.Colors.to_int(v))

        %{"ctor" => "TextColor", "args" => [v]} ->
          Map.put(acc, "text_color", Elmx.Runtime.Pebble.Colors.to_int(v))
        %{"ctor" => "CompositingMode", "args" => [v]} -> Map.put(acc, "compositing_mode", v)
        {ctor, [v]} when is_atom(ctor) -> Map.put(acc, context_key(ctor), v)
        _ -> acc
      end
    end)
  end

  def coerce_context_settings(other), do: other

  def context_key(:StrokeWidth), do: "stroke_width"
  def context_key(:Antialiased), do: "antialiased"
  def context_key(:StrokeColor), do: "stroke_color"
  def context_key(:FillColor), do: "fill_color"
  def context_key(:TextColor), do: "text_color"
  def context_key(:CompositingMode), do: "compositing_mode"
  def context_key(other), do: to_string(other)

end
