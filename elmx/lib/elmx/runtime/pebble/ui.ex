defmodule Elmx.Runtime.Pebble.Ui do
  @moduledoc false

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
  def clear(color \\ 0xFFFFFFFF) do
    %{type: "clear", label: "clear", color: color_value(color)}
  end

  @spec named_color(String.t()) :: integer()
  def named_color("white"), do: 0xFFFFFFFF
  def named_color("black"), do: 0xFF000000
  def named_color(_), do: 0xFF000000

  @spec fill_rect(term(), term()) :: map()
  def fill_rect(bounds, color),
    do: %{type: "fillRect", label: "fillRect", bounds: bounds, color: color_value(color)}

  @spec text(term(), term(), term(), term()) :: map()
  def text(font, options, bounds, value),
    do: %{type: "text", label: to_string(value), font: font, bounds: bounds, options: options}

  @spec text_int(term(), term(), term()) :: map()
  def text_int(font, pos, value),
    do: %{type: "text", label: Integer.to_string(value), font: font, position: pos}

  @spec text_label(term(), term(), term()) :: map()
  def text_label(font, pos, label),
    do: %{type: "text", label: to_string(label), font: font, position: pos}

  @spec rect(term(), term()) :: map()
  def rect(bounds, color), do: %{type: "rect", label: "rect", bounds: bounds, color: color_value(color)}

  @spec line(term(), term(), term()) :: map()
  def line(from, to, color \\ 0xFF000000) do
    %{type: "line", label: "line", from: from, to: to, color: color_value(color)}
  end

  @spec circle(term(), term()) :: map()
  def circle(center, radius), do: %{type: "circle", label: "circle", center: center, radius: radius}

  @spec fill_circle(term(), term()) :: map()
  def fill_circle(center, color),
    do: %{type: "fillCircle", label: "fillCircle", center: center, color: color_value(color)}

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
  def pixel(pos, color), do: %{type: "pixel", label: "pixel", position: pos, color: color_value(color)}

  @spec context_setting(String.t(), term()) :: map()
  def context_setting(key, value), do: %{type: "contextSetting", key: key, value: value}

  @spec round_rect(term(), term(), term()) :: map()
  def round_rect(bounds, _radius, color),
    do: %{type: "roundRect", label: "roundRect", bounds: bounds, color: color_value(color)}

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

  @spec draw_rotated_bitmap(term(), term(), term()) :: map()
  def draw_rotated_bitmap(resource, origin, rotation),
    do: %{type: "drawRotatedBitmap", label: "drawRotatedBitmap", resource: resource, origin: origin, rotation: rotation}

  @spec compositing_mode(term()) :: map()
  def compositing_mode(mode), do: %{type: "compositingMode", label: "compositingMode", mode: mode}

  @spec rotation_from_degrees(term()) :: term()
  def rotation_from_degrees(degrees), do: degrees

  defp draw_op(op) when is_map(op), do: op
  defp draw_op(other), do: %{type: "drawOp", label: inspect(other)}

  defp normalize_child(%{type: _} = node), do: node
  defp normalize_child(other), do: %{type: "node", label: inspect(other)}

  defp expr_node(value), do: %{type: "expr", label: inspect(value)}

  defp color_value(color) when is_integer(color), do: color
  defp color_value(color), do: color

  defp context_style(settings) when is_list(settings) do
    Enum.reduce(settings, %{}, fn
      %{type: "contextSetting", key: key, value: value}, acc ->
        Map.put(acc, key, value)

      %{key: key, value: value}, acc when is_binary(key) ->
        Map.put(acc, key, value)

      other, acc ->
        Map.put(acc, "setting", other)
    end)
  end
end
