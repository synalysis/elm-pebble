defmodule IdeWeb.WorkspaceLive.DebuggerPage.SvgRender do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerPreview
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: SupportTypes

  @type svg_op :: SupportTypes.svg_op()

  @spec arc_path(svg_op()) :: String.t()
  def arc_path(op), do: DebuggerPreview.arc_path(op)

  @spec arc_sector_path(svg_op()) :: String.t()
  def arc_sector_path(op) when is_map(op), do: DebuggerPreview.pie_sector_path(op)

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
  def text_y(%{y: y, h: h}) when is_number(y) and is_number(h) and h > 0, do: y + h / 2
  def text_y(%{y: y}) when is_number(y), do: y
  def text_y(_op), do: 0

  @spec text_font_size(svg_op()) :: pos_integer()
  def text_font_size(op) do
    cap =
      op
      |> box_text_height()
      |> pebble_system_font_cap_height()

    case Map.get(op, :h) do
      h when is_integer(h) and h > 0 -> min(cap, h)
      _ -> cap
    end
  end

  @spec text_clippable?(svg_op()) :: boolean()
  def text_clippable?(%{kind: :text_label, w: w, h: h})
      when is_number(w) and w > 0 and is_number(h) and h > 0,
      do: true

  def text_clippable?(_op), do: false

  @spec text_clip_id(String.t(), non_neg_integer()) :: String.t()
  def text_clip_id(svg_id, index) when is_binary(svg_id) and is_integer(index) and index >= 0 do
    "#{svg_id}-text-#{index}"
  end

  @spec box_text_height(svg_op()) :: pos_integer() | nil
  defp box_text_height(%{h: height}) when is_integer(height) and height > 0, do: height

  defp box_text_height(%{font_size: size}) when is_integer(size) and size > 0, do: size
  defp box_text_height(_op), do: nil

  # Mirrors Pebble `system_font_for_height` in pebble_app_template.c: box height selects
  # a system font cap size, not the SVG em size of the full bounding box.
  @spec pebble_system_font_cap_height(pos_integer() | nil) :: pos_integer()
  defp pebble_system_font_cap_height(height) when is_integer(height) and height > 0 do
    cond do
      height <= 18 -> 18
      height <= 28 -> 24
      height <= 36 -> 28
      true -> 42
    end
  end

  defp pebble_system_font_cap_height(_height), do: 11

  @spec text_anchor(svg_op()) :: String.t() | nil
  def text_anchor(%{text_align: "left", w: w}) when is_number(w), do: "start"
  def text_anchor(%{text_align: "center", w: w}) when is_number(w), do: "middle"
  def text_anchor(%{text_align: "right", w: w}) when is_number(w), do: "end"
  def text_anchor(_op), do: nil

  @spec text_baseline(svg_op()) :: String.t() | nil
  def text_baseline(%{h: h}) when is_number(h) and h > 0, do: "middle"
  def text_baseline(_op), do: nil

  @spec color(integer() | nil, String.t()) :: String.t()
  def color(value, fallback), do: DebuggerPreview.pebble_color_to_svg(value, fallback)
end
