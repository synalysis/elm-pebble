defmodule IdeWeb.WorkspaceLive.DebuggerPage.SvgRender do
  @moduledoc false

  alias Ide.Pebble.TextLayout
  alias IdeWeb.WorkspaceLive.DebuggerPreview
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: SupportTypes

  @type svg_op :: SupportTypes.svg_op()

  # CSS sans-serif fills more of the em-square than Pebble Gothic ink. Scale the
  # selected Gothic bucket down so date/time bands match the emulator visually.
  @gothic_to_sans_num 3
  @gothic_to_sans_den 4

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

  # Pebble draws the first line against the top of the GRect, but Gothic glyphs
  # sit below the line-box top (internal bearing). Nudge SVG text down so dial
  # labels and corners line up with the emulator — a constant upward error looks
  # larger at the top of a circular scale than at the bottom.
  # When the project declared a font height, also apply the same tight-box lift
  # as `center_aligned_text_rect` in pebble_app_template.c.
  @spec text_y(svg_op()) :: number()
  def text_y(%{y: y} = op) when is_number(y) do
    y + text_box_metrics(op).bearing
  end

  def text_y(_op), do: 0

  @spec text_font_size(svg_op()) :: pos_integer()
  def text_font_size(op), do: text_box_metrics(op).font_size

  @type text_box_metrics :: %{font_size: pos_integer(), bearing: number()}

  @spec text_box_metrics(svg_op()) :: text_box_metrics()
  defp text_box_metrics(op) do
    declared = declared_font_height(op)

    gothic =
      if declared > 0 do
        declared
      else
        op
        |> box_text_height()
        |> pebble_system_font_cap_height()
      end

    approx = gothic_to_sans_px(gothic)

    metrics =
      case Map.get(op, :h) do
        h when is_integer(h) and h > 0 and h < gothic ->
          tight_text_metrics(gothic, h, approx)

        h when is_integer(h) and h > 0 ->
          font = min(approx, h)
          bearing = max(0, min(gothic_top_bearing(gothic), h - font))
          %{font_size: font, bearing: bearing}

        _ ->
          %{font_size: approx, bearing: gothic_top_bearing(gothic)}
      end

    lift = center_aligned_lift_px(op, declared)
    %{metrics | bearing: metrics.bearing - lift}
  end

  defp declared_font_height(%{font_height: height}) when is_integer(height) and height > 0,
    do: height

  defp declared_font_height(%{"font_height" => height})
       when is_integer(height) and height > 0,
       do: height

  defp declared_font_height(_op), do: 0

  defp center_aligned_lift_px(op, declared) do
    h = Map.get(op, :h) || Map.get(op, "h")

    if center_aligned?(op) and is_integer(h) do
      TextLayout.center_aligned_lift(h, declared)
    else
      0
    end
  end

  defp center_aligned?(op) do
    case Map.get(op, :text_align) || Map.get(op, "text_align") do
      "left" -> false
      "right" -> false
      _ -> true
    end
  end

  @spec tight_text_metrics(pos_integer(), pos_integer(), pos_integer()) :: text_box_metrics()
  defp tight_text_metrics(gothic, h, approx) when gothic > h and h > 0 do
    # Short GRects select a larger Gothic bucket than their height. Emulator ink
    # for Yes dial labels (h=12) starts ~7px below the box top. CSS sans AA sits
    # slightly below the em-box top; a half-pixel inset balances top vs bottom
    # dial labels. The glyph may extend a few px past `h` — `text_clip_height/1`
    # expands the clip so bottoms are not cut off (sans fills the em-square;
    # Gothic ink does not).
    desired = gothic_top_bearing(gothic)
    sans_aa_inset = 1.5
    bearing = max(0, min(h - 1, gothic - h + desired - sans_aa_inset))
    font = max(4, min(approx, h - div(h, 4)))

    %{font_size: font, bearing: bearing}
  end

  @spec text_clippable?(svg_op()) :: boolean()
  def text_clippable?(%{kind: :text_label, w: w, h: h})
      when is_number(w) and w > 0 and is_number(h) and h > 0,
      do: true

  def text_clippable?(_op), do: false

  @doc """
  Clip height for a text label. At least the GRect height, and tall enough to
  include `bearing + font_size` so CSS sans glyphs are not cut off at the bottom
  when short boxes select a larger Gothic-equivalent face.
  """
  @spec text_clip_height(svg_op()) :: number()
  def text_clip_height(%{h: h} = op) when is_number(h) and h > 0 do
    metrics = text_box_metrics(op)
    glyph_extent = metrics.bearing + metrics.font_size
    max(h, glyph_extent)
  end

  def text_clip_height(_op), do: 0

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

  @spec gothic_to_sans_px(pos_integer()) :: pos_integer()
  defp gothic_to_sans_px(gothic) when is_integer(gothic) and gothic > 0 do
    max(1, div(gothic * @gothic_to_sans_num + div(@gothic_to_sans_den, 2), @gothic_to_sans_den))
  end

  defp gothic_to_sans_px(_gothic), do: 1

  @spec gothic_top_bearing(pos_integer()) :: non_neg_integer()
  defp gothic_top_bearing(gothic) when is_integer(gothic) and gothic > 0, do: div(gothic, 8)
  defp gothic_top_bearing(_gothic), do: 0

  @spec text_anchor(svg_op()) :: String.t() | nil
  def text_anchor(%{text_align: "left", w: w}) when is_number(w), do: "start"
  def text_anchor(%{text_align: "center", w: w}) when is_number(w), do: "middle"
  def text_anchor(%{text_align: "right", w: w}) when is_number(w), do: "end"
  def text_anchor(_op), do: nil

  # SVG: top of the em box at `text_y` ≈ Pebble first-line-at-top-of-rect, after
  # `text_top_bearing/1` accounts for Gothic's internal top padding.
  @spec text_baseline(svg_op()) :: String.t() | nil
  def text_baseline(%{h: h}) when is_number(h) and h > 0, do: "text-before-edge"
  def text_baseline(_op), do: nil

  @spec color(integer() | nil, String.t()) :: String.t()
  def color(value, fallback), do: DebuggerPreview.pebble_color_to_svg(value, fallback)
end
