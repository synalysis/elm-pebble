defmodule IdeWeb.WorkspaceLive.DebuggerPage.SvgRender do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerPreview
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: SupportTypes

  @type svg_op :: SupportTypes.svg_op()

  @spec arc_path(svg_op()) :: String.t()
  def arc_path(op), do: DebuggerPreview.arc_path(op)

  @spec arc_sector_path(svg_op()) :: String.t()
  def arc_sector_path(op) when is_map(op) do
    arc = DebuggerPreview.arc_path(op)

    if arc == "" do
      ""
    else
      cx = (op.x || 0) + max(op.w || 1, 1) / 2.0
      cy = (op.y || 0) + max(op.h || 1, 1) / 2.0
      arc <> " L #{Float.round(cx, 2)} #{Float.round(cy, 2)} Z"
    end
  end

  def arc_sector_path(_op), do: ""

  @spec path_d(svg_op(), boolean()) :: String.t()
  def path_d(op, close_shape?) when is_map(op) and is_boolean(close_shape?) do
    DebuggerPreview.svg_path_d(op, close_shape?)
  end

  def path_d(_op, _close_shape?), do: ""

  @spec text_x(svg_op()) :: number()
  def text_x(%{text_align: "left", x: x}) when is_number(x), do: x

  def text_x(%{text_align: "right", x: x, w: w}) when is_number(x) and is_number(w),
    do: x + w

  def text_x(%{x: x, w: w}) when is_number(x) and is_number(w), do: x + w / 2
  def text_x(%{x: x}) when is_number(x), do: x
  def text_x(_op), do: 0

  @spec text_y(svg_op()) :: number()
  def text_y(%{y: y, w: w, h: h})
      when is_number(y) and is_number(w) and is_number(h) and h > 0,
      do: y + 1

  def text_y(%{y: y, h: h}) when is_number(y) and is_number(h), do: y + h / 2
  def text_y(%{y: y}) when is_number(y), do: y
  def text_y(_op), do: 0

  @spec text_font_size(svg_op()) :: pos_integer()
  def text_font_size(%{font_size: size}) when is_integer(size) and size > 0, do: size
  def text_font_size(%{h: height}) when is_integer(height) and height > 0, do: height
  def text_font_size(_op), do: 11

  @spec text_anchor(svg_op()) :: String.t() | nil
  def text_anchor(%{text_align: "left", w: w}) when is_number(w), do: "start"
  def text_anchor(%{text_align: "center", w: w}) when is_number(w), do: "middle"
  def text_anchor(%{text_align: "right", w: w}) when is_number(w), do: "end"
  def text_anchor(_op), do: nil

  @spec text_baseline(svg_op()) :: String.t() | nil
  def text_baseline(%{w: w, h: h}) when is_number(w) and is_number(h) and h > 0,
    do: "hanging"

  def text_baseline(%{h: h}) when is_number(h), do: "middle"
  def text_baseline(_op), do: nil

  @spec color(integer() | nil, String.t()) :: String.t()
  def color(value, fallback), do: DebuggerPreview.pebble_color_to_svg(value, fallback)
end
