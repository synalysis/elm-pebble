defmodule Elmx.Runtime.Pebble.Ui.Primitives do
  @moduledoc false

  alias Elmx.Runtime.Pebble.Colors
  alias Elmx.Runtime.Pebble.TextOptions
  alias Elmx.Runtime.Pebble.Ui.Helpers
  alias Elmx.Types

  @color_context_keys ~w(stroke_color fill_color text_color)

  def clear(color \\ :black) do
    %{type: "clear", label: "clear", color: Helpers.color_value(color)}
  end

  @spec named_color(String.t()) :: integer()
  def named_color(name) when is_binary(name), do: Colors.named(name)

  @spec fill_rect(Types.ui_bounds(), Types.ui_color()) :: Types.ui_node()
  def fill_rect(bounds, color),
    do: %{type: "fillRect", label: "fillRect", bounds: bounds, color: Helpers.color_value(color)}

  @spec text(Types.ui_font(), Types.ui_text_options(), Types.ui_bounds(), Types.string_like()) ::
          Types.ui_node()
  def text(font, options, bounds, value) do
    {text_align, text_overflow} = TextOptions.fields(options)

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

  @spec text_int(Types.ui_font(), Types.ui_point(), Types.ui_coord()) :: Types.ui_node()
  def text_int(font, pos, value) do
    {x, y} = Helpers.point_xy(pos)
    text = Integer.to_string(Helpers.int_value(value))

    %{
      type: "textInt",
      label: text,
      text: text,
      font: font,
      position: %{x: x, y: y},
      x: x,
      y: y,
      value: Helpers.int_value(value)
    }
  end

  @spec text_label(Types.ui_font(), Types.ui_point(), Types.ui_label()) :: Types.ui_node()
  def text_label(font, pos, label) do
    {x, y} = Helpers.point_xy(pos)
    text = Helpers.label_display_text(label)

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

  @spec rect(Types.ui_bounds(), Types.ui_color()) :: Types.ui_node()
  def rect(bounds, color), do: %{type: "rect", label: "rect", bounds: bounds, color: Helpers.color_value(color)}

  @spec line(Types.ui_point(), Types.ui_point(), Types.ui_color()) :: Types.ui_node()
  def line(from, to, color \\ :black) do
    {x1, y1} = Helpers.point_xy(from)
    {x2, y2} = Helpers.point_xy(to)

    %{
      type: "line",
      label: "line",
      x1: x1,
      y1: y1,
      x2: x2,
      y2: y2,
      color: Helpers.color_value(color)
    }
  end

  @spec circle(Types.ui_point(), Types.ui_coord(), Types.ui_color()) :: Types.ui_node()
  def circle(center, radius, color) do
    {cx, cy} = Helpers.point_xy(center)

    %{
      type: "circle",
      label: "circle",
      cx: cx,
      cy: cy,
      r: Helpers.int_value(radius),
      color: Helpers.color_value(color)
    }
  end

  def circle(center, radius), do: circle(center, radius, :black)

  @spec fill_circle(Types.ui_point(), Types.ui_coord(), Types.ui_color()) :: Types.ui_node()
  def fill_circle(center, radius, color) do
    {cx, cy} = Helpers.point_xy(center)

    %{
      type: "fillCircle",
      label: "fillCircle",
      cx: cx,
      cy: cy,
      r: Helpers.int_value(radius),
      color: Helpers.color_value(color)
    }
  end

  def fill_circle(center, color),
    do: fill_circle(center, 0, color)

  @spec fill_radial(Types.ui_bounds(), Types.ui_coord(), Types.ui_coord()) :: Types.ui_node()
  def fill_radial(bounds, start_angle, end_angle),
    do: %{
      type: "fillRadial",
      label: "fillRadial",
      bounds: bounds,
      start_angle: start_angle,
      end_angle: end_angle
    }

  @spec pixel(Types.ui_point(), Types.ui_color()) :: Types.ui_node()
  def pixel(pos, color) do
    {x, y} = Helpers.point_xy(pos)

    %{type: "pixel", label: "pixel", x: x, y: y, color: Helpers.color_value(color)}
  end

  @spec context_setting(String.t(), Types.ui_color() | Types.ui_coord()) :: Types.ui_node()
  def context_setting(key, value) when key in @color_context_keys,
    do: %{type: "contextSetting", key: key, value: Helpers.color_value(value)}

  def context_setting(key, value), do: %{type: "contextSetting", key: key, value: value}

  @spec round_rect(Types.ui_bounds(), Types.ui_coord(), Types.ui_color()) :: Types.ui_node()
  def round_rect(bounds, radius, color) do
    {x, y, w, h} = Helpers.bounds_xywh(bounds)

    %{
      type: "roundRect",
      label: "roundRect",
      x: x,
      y: y,
      w: w,
      h: h,
      radius: Helpers.int_value(radius),
      color: Helpers.color_value(color)
    }
  end

  @spec arc(Types.ui_bounds(), Types.ui_coord(), Types.ui_coord()) :: Types.ui_node()
  def arc(bounds, _start, _end), do: %{type: "arc", label: "arc", bounds: bounds}

  @spec path(list(), Types.ui_point(), Types.ui_coord()) :: Types.ui_node()
  def path(points, origin, _rotation), do: %{type: "path", label: "path", points: points, origin: origin}

  @spec path_outline(Types.ui_path()) :: Types.ui_node()
  def path_outline(path), do: %{type: "pathOutline", label: "pathOutline", path: path}

  @spec path_filled(Types.ui_path()) :: Types.ui_node()
  def path_filled(path), do: %{type: "pathFilled", label: "pathFilled", path: path}

  @spec path_outline_open(Types.ui_path()) :: Types.ui_node()
  def path_outline_open(path), do: %{type: "pathOutlineOpen", label: "pathOutlineOpen", path: path}

  @spec compositing_mode(Types.ui_compositing_mode()) :: Types.ui_node()
  def compositing_mode(mode), do: %{type: "compositingMode", label: "compositingMode", mode: mode}

  @spec rotation_from_degrees(Types.ui_coord()) :: number()
  def rotation_from_degrees(degrees), do: degrees
end
