defmodule Elmx.Runtime.Pebble.Ui do
  @moduledoc false

  alias Elmx.Runtime.Pebble.Colors

  @color_context_keys ~w(stroke_color fill_color text_color)

  @spec window_stack(list()) :: map()
  def window_stack(windows) when is_list(windows),
    do: %{type: "windowStack", label: "", children: Enum.map(windows, &normalize_child/1)}

  @spec window(term(), list()) :: map()
  def window(id, layers) do
  children = [expr_node(id) | Enum.map(layers, &normalize_child/1)]
    %{type: "window", label: "", children: children}
  end

  @spec canvas_layer(term(), list()) :: map()
  def canvas_layer(z, ops) do
    %{type: "canvasLayer", label: "", children: [expr_node(z) | Enum.map(ops, &draw_op/1)]}
  end

  @spec group(map()) :: map()
  def group(%{style: style, ops: ops}) when is_map(style) do
    %{type: "group", label: "", children: Enum.map(ops, &draw_op/1), style: style}
  end

  def group(other), do: %{type: "group", label: "", children: [normalize_child(other)]}

  @spec context(list(), list()) :: map()
  def context(settings, ops) when is_list(settings) and is_list(ops) do
    %{type: "group", label: "", children: Enum.map(ops, &draw_op/1), style: context_style(settings)}
  end

  @spec to_ui_node(term()) :: map()
  def to_ui_node(ops) when is_list(ops) do
    window_stack([
      window(1, [
        canvas_layer(1, ops)
      ])
    ])
  end

  def to_ui_node(node), do: normalize_child(node)

  @spec draw_bitmap_in_rect(term(), term()) :: map()
  def draw_bitmap_in_rect(resource, bounds) when is_map(bounds) do
    %{
      type: "drawBitmapInRect",
      label: "drawBitmapInRect",
      resource: resource,
      bounds: bounds
    }
  end

  def draw_bitmap_in_rect(resource, bounds),
    do: %{
      type: "drawBitmapInRect",
      label: "drawBitmapInRect",
      resource: inspect(resource),
      bounds: bounds
    }

  @spec clear(term()) :: map()
  def clear(color \\ :black) do
    %{type: "clear", label: "clear", color: color_value(color)}
  end

  @spec named_color(String.t()) :: integer()
  def named_color(name) when is_binary(name), do: Colors.named(name)

  @spec fill_rect(term(), term()) :: map()
  def fill_rect(bounds, color),
    do: %{type: "fillRect", label: "fillRect", bounds: bounds, color: color_value(color)}

  @spec text(term(), term(), term(), term()) :: map()
  def text(font, options, bounds, value) do
    {text_align, text_overflow} = Elmx.Runtime.Pebble.TextOptions.fields(options)

    %{
      type: "text",
      label: to_string(value),
      text: to_string(value),
      font: font,
      bounds: bounds,
      options: options,
      text_align: text_align,
      text_overflow: text_overflow
    }
  end

  @spec text_int(term(), term(), term()) :: map()
  def text_int(font, pos, value) do
    {x, y} = point_xy(pos)
    text = Integer.to_string(int_value(value))

    %{
      type: "textInt",
      label: text,
      text: text,
      font: font,
      position: %{x: x, y: y},
      x: x,
      y: y,
      value: int_value(value)
    }
  end

  @spec text_label(term(), term(), term()) :: map()
  def text_label(font, pos, label) do
    {x, y} = point_xy(pos)
    text = label_display_text(label)

    %{
      type: "textLabel",
      label: text,
      text: text,
      font: font,
      position: %{x: x, y: y},
      x: x,
      y: y
    }
  end

  @spec rect(term(), term()) :: map()
  def rect(bounds, color), do: %{type: "rect", label: "rect", bounds: bounds, color: color_value(color)}

  @spec line(term(), term(), term()) :: map()
  def line(from, to, color \\ :black) do
    {x1, y1} = point_xy(from)
    {x2, y2} = point_xy(to)

    %{
      type: "line",
      label: "line",
      x1: x1,
      y1: y1,
      x2: x2,
      y2: y2,
      color: color_value(color)
    }
  end

  @spec circle(term(), term(), term()) :: map()
  def circle(center, radius, color) do
    {cx, cy} = point_xy(center)

    %{
      type: "circle",
      label: "circle",
      cx: cx,
      cy: cy,
      r: int_value(radius),
      color: color_value(color)
    }
  end

  def circle(center, radius), do: circle(center, radius, :black)

  @spec fill_circle(term(), term(), term()) :: map()
  def fill_circle(center, radius, color) do
    {cx, cy} = point_xy(center)

    %{
      type: "fillCircle",
      label: "fillCircle",
      cx: cx,
      cy: cy,
      r: int_value(radius),
      color: color_value(color)
    }
  end

  def fill_circle(center, color),
    do: fill_circle(center, 0, color)

  @spec fill_radial(term(), term(), term()) :: map()
  def fill_radial(bounds, start_angle, end_angle),
    do: %{
      type: "fillRadial",
      label: "fillRadial",
      bounds: bounds,
      start_angle: start_angle,
      end_angle: end_angle
    }

  @spec pixel(term(), term()) :: map()
  def pixel(pos, color) do
    {x, y} = point_xy(pos)

    %{type: "pixel", label: "pixel", x: x, y: y, color: color_value(color)}
  end

  @spec context_setting(String.t(), term()) :: map()
  def context_setting(key, value) when key in @color_context_keys,
    do: %{type: "contextSetting", key: key, value: color_value(value)}

  def context_setting(key, value), do: %{type: "contextSetting", key: key, value: value}

  @spec round_rect(term(), term(), term()) :: map()
  def round_rect(bounds, radius, color) do
    {x, y, w, h} = bounds_xywh(bounds)

    %{
      type: "roundRect",
      label: "roundRect",
      x: x,
      y: y,
      w: w,
      h: h,
      radius: int_value(radius),
      color: color_value(color)
    }
  end

  @spec arc(term(), term(), term()) :: map()
  def arc(bounds, _start, _end), do: %{type: "arc", label: "arc", bounds: bounds}

  @spec path(list(), term(), term()) :: map()
  def path(points, origin, _rotation), do: %{type: "path", label: "path", points: points, origin: origin}

  @spec path_outline(term()) :: map()
  def path_outline(path), do: %{type: "pathOutline", label: "pathOutline", path: path}

  @spec path_filled(term()) :: map()
  def path_filled(path), do: %{type: "pathFilled", label: "pathFilled", path: path}

  @spec path_outline_open(term()) :: map()
  def path_outline_open(path), do: %{type: "pathOutlineOpen", label: "pathOutlineOpen", path: path}

  @spec draw_vector_at(term(), term(), term(), term()) :: map()
  def draw_vector_at(resource, frame, origin, rotation),
    do: %{type: "drawVectorAt", label: "drawVectorAt", resource: resource, frame: frame, origin: origin, rotation: rotation}

  def draw_vector_at(resource, origin),
    do: draw_vector_at(resource, 0, origin, 0)

  @spec draw_vector_sequence_at(term(), term(), term(), term()) :: map()
  def draw_vector_sequence_at(resource, frame, origin, rotation),
    do: %{
      type: "drawVectorSequenceAt",
      label: "drawVectorSequenceAt",
      resource: resource,
      frame: frame,
      origin: origin,
      rotation: rotation
    }

  def draw_vector_sequence_at(resource, origin),
    do: draw_vector_sequence_at(resource, 0, origin, 0)

  @spec draw_bitmap_sequence_at(term(), term(), term(), term()) :: map()
  def draw_bitmap_sequence_at(resource, frame, origin, rotation),
    do: %{
      type: "drawBitmapSequenceAt",
      label: "drawBitmapSequenceAt",
      resource: resource,
      frame: frame,
      origin: origin,
      rotation: rotation
    }

  def draw_bitmap_sequence_at(resource, origin),
    do: draw_bitmap_sequence_at(resource, 0, origin, 0)

  @spec draw_rotated_bitmap(term(), term(), term(), term()) :: map()
  def draw_rotated_bitmap(resource, bounds, rotation, center) when is_map(bounds) do
    %{
      type: "drawRotatedBitmap",
      label: "drawRotatedBitmap",
      resource: resource,
      bounds: bounds,
      rotation: rotation,
      origin: center
    }
  end

  def draw_rotated_bitmap(resource, origin, rotation),
    do: draw_rotated_bitmap(resource, %{x: 0, y: 0, w: 0, h: 0}, rotation, origin)

  @spec compositing_mode(term()) :: map()
  def compositing_mode(mode), do: %{type: "compositingMode", label: "compositingMode", mode: mode}

  @spec rotation_from_degrees(term()) :: term()
  def rotation_from_degrees(degrees), do: degrees

  defp draw_op(op) when is_map(op), do: op
  defp draw_op(other), do: %{type: "drawOp", label: inspect(other)}

  defp normalize_child(%{type: _} = node), do: node
  defp normalize_child(other), do: %{type: "node", label: inspect(other)}

  defp expr_node(value), do: %{type: "expr", label: inspect(value)}

  defp color_value(color), do: Colors.to_int(color)

  defp point_xy(%{"x" => x, "y" => y}), do: {int_value(x), int_value(y)}
  defp point_xy(%{x: x, y: y}), do: {int_value(x), int_value(y)}
  defp point_xy({x, y}), do: {int_value(x), int_value(y)}
  defp point_xy(_), do: {0, 0}

  defp label_display_text(label) do
    case label do
      :WaitingForCompanion -> "Waiting for companion app"
      "WaitingForCompanion" -> "Waiting for companion app"
      atom when is_atom(atom) -> Atom.to_string(atom)
      other -> to_string(other)
    end
  end

  defp int_value(value) when is_integer(value), do: value
  defp int_value(value) when is_float(value), do: trunc(value)
  defp int_value(_), do: 0

  defp bounds_xywh(%{"x" => x, "y" => y, "w" => w, "h" => h}),
    do: {int_value(x), int_value(y), int_value(w), int_value(h)}

  defp bounds_xywh(%{x: x, y: y, w: w, h: h}),
    do: {int_value(x), int_value(y), int_value(w), int_value(h)}

  defp bounds_xywh({x, y, w, h}) when is_integer(x),
    do: {int_value(x), int_value(y), int_value(w), int_value(h)}

  defp bounds_xywh([x, y, w, h]) when is_integer(x),
    do: {int_value(x), int_value(y), int_value(w), int_value(h)}

  defp bounds_xywh(_), do: {0, 0, 0, 0}

  defp context_style(settings) when is_list(settings) do
    Enum.reduce(settings, %{}, fn
      %{type: "contextSetting", key: key, value: value}, acc ->
        Map.put(acc, context_style_key(key), color_value(value))

      %{"type" => "contextSetting", "key" => key, "value" => value}, acc ->
        Map.put(acc, context_style_key(key), color_value(value))

      %{key: key, value: value}, acc when is_binary(key) ->
        Map.put(acc, context_style_key(key), color_value(value))

      %{"key" => key, "value" => value}, acc when is_binary(key) ->
        Map.put(acc, context_style_key(key), color_value(value))

      other, acc ->
        Map.put(acc, "setting", other)
    end)
  end

  defp context_style_key("strokeWidth"), do: "stroke_color"
  defp context_style_key("strokeColor"), do: "stroke_color"
  defp context_style_key("fillColor"), do: "fill_color"
  defp context_style_key("textColor"), do: "text_color"
  defp context_style_key("stroke_width"), do: "stroke_color"
  defp context_style_key("fill_color"), do: "fill_color"
  defp context_style_key("text_color"), do: "text_color"
  defp context_style_key("antialiased"), do: "antialiased"
  defp context_style_key("compositingMode"), do: "compositing_mode"
  defp context_style_key(key) when is_binary(key), do: key
end
