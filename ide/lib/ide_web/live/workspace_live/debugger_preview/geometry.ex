defmodule IdeWeb.WorkspaceLive.DebuggerPreview.Geometry do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: PreviewTypes

  @type svg_op :: PreviewTypes.svg_op()
  @type wire_value :: PreviewTypes.wire_value()

  @spec svg_path_d(svg_op(), boolean()) :: String.t()
  def svg_path_d(op, close_shape?) when is_map(op) and is_boolean(close_shape?) do
    points = Map.get(op, :points, []) || Map.get(op, "points", []) || []
    offset_x = Map.get(op, :offset_x, 0) || Map.get(op, "offset_x", 0) || 0
    offset_y = Map.get(op, :offset_y, 0) || Map.get(op, "offset_y", 0) || 0
    rotation = Map.get(op, :rotation, 0) || Map.get(op, "rotation", 0) || 0
    rotation_rad = rotation * 2.0 * :math.pi() / 65_536.0
    cos_r = :math.cos(rotation_rad)
    sin_r = :math.sin(rotation_rad)

    transformed =
      points
      |> Enum.map(fn point ->
        case normalize_point_pair(point) do
          {:ok, [x, y]} ->
            xr = x * cos_r - y * sin_r
            yr = x * sin_r + y * cos_r
            {xr + offset_x, yr + offset_y}

          :error ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    case transformed do
      [] ->
        ""

      [{sx, sy} | rest] ->
        base =
          "M #{Float.round(sx, 2)} #{Float.round(sy, 2)} " <>
            Enum.map_join(rest, " ", fn {x, y} ->
              "L #{Float.round(x, 2)} #{Float.round(y, 2)}"
            end)

        if close_shape?, do: base <> " Z", else: base
    end
  end

  def svg_path_d(_op, _close_shape?), do: ""

  @spec arc_path(svg_op()) :: String.t()
  def arc_path(op) when is_map(op) do
    x = op.x || 0
    y = op.y || 0
    w = max(op.w || 1, 1)
    h = max(op.h || 1, 1)
    start_angle = op.start_angle || 0
    end_angle = op.end_angle || 16_384

    cx = x + w / 2.0
    cy = y + h / 2.0
    rx = w / 2.0
    ry = h / 2.0

    start_rad = pebble_angle_to_rad(start_angle)
    finish_rad = pebble_angle_to_rad(end_angle)

    sweep_rad =
      if finish_rad >= start_rad,
        do: finish_rad - start_rad,
        else: finish_rad - start_rad + 2.0 * :math.pi()

    large_arc = if sweep_rad > :math.pi(), do: 1, else: 0

    sx = cx + rx * :math.cos(start_rad)
    sy = cy + ry * :math.sin(start_rad)
    ex = cx + rx * :math.cos(finish_rad)
    ey = cy + ry * :math.sin(finish_rad)

    "M #{Float.round(sx, 2)} #{Float.round(sy, 2)} A #{Float.round(rx, 2)} #{Float.round(ry, 2)} 0 #{large_arc} 1 #{Float.round(ex, 2)} #{Float.round(ey, 2)}"
  end

  def arc_path(_), do: ""

  @spec normalize_point_pair(wire_value()) :: {:ok, [integer()]} | :error
  def normalize_point_pair([x, y]) when is_integer(x) and is_integer(y), do: {:ok, [x, y]}
  def normalize_point_pair({x, y}) when is_integer(x) and is_integer(y), do: {:ok, [x, y]}

  def normalize_point_pair(%{"x" => x, "y" => y}) when is_integer(x) and is_integer(y),
    do: {:ok, [x, y]}

  def normalize_point_pair(%{x: x, y: y}) when is_integer(x) and is_integer(y),
    do: {:ok, [x, y]}

  def normalize_point_pair(_), do: :error

  @doc """
  Converts Pebble color integers to CSS colors for the debugger SVG preview.

  Supports indexed black/white (`0`/`1`), 8-bit `GColor8`, and 32-bit `GColor` ARGB8.
  """
  @spec pebble_color_to_svg(integer() | nil, String.t()) :: String.t()
  def pebble_color_to_svg(value, fallback \\ "#111111")

  def pebble_color_to_svg(0, _fallback), do: "white"
  def pebble_color_to_svg(1, _fallback), do: "#111111"

  def pebble_color_to_svg(value, _fallback) when is_integer(value) and value >= 0x100 do
    argb8_to_svg(value)
  end

  def pebble_color_to_svg(value, _fallback) when is_integer(value) do
    gcolor8_to_svg(value)
  end

  def pebble_color_to_svg(_value, fallback), do: fallback

  @spec pebble_angle_to_rad(integer()) :: float()
  defp pebble_angle_to_rad(angle) when is_integer(angle) do
    angle * 2.0 * :math.pi() / 65_536.0 - :math.pi() / 2.0
  end

  defp pebble_angle_to_rad(_), do: -:math.pi() / 2.0

  @spec argb8_to_svg(integer()) :: String.t()
  defp argb8_to_svg(argb) when is_integer(argb) do
    alpha = Bitwise.band(Bitwise.bsr(argb, 24), 0xFF)
    red = Bitwise.band(Bitwise.bsr(argb, 16), 0xFF)
    green = Bitwise.band(Bitwise.bsr(argb, 8), 0xFF)
    blue = Bitwise.band(argb, 0xFF)

    if alpha >= 255 do
      hex_rgb(red, green, blue)
    else
      a = Float.round(alpha / 255.0, 2)
      "rgba(#{red}, #{green}, #{blue}, #{a})"
    end
  end

  @spec gcolor8_to_svg(integer()) :: String.t()
  defp gcolor8_to_svg(packed) when is_integer(packed) do
    alpha = Bitwise.band(Bitwise.bsr(packed, 6), 0x03)
    red = Bitwise.band(Bitwise.bsr(packed, 4), 0x03)
    green = Bitwise.band(Bitwise.bsr(packed, 2), 0x03)
    blue = Bitwise.band(packed, 0x03)

    gcolor8_rgba_float(red, green, blue, alpha)
  end

  @spec gcolor8_rgba_float(integer(), integer(), integer(), integer()) :: String.t()
  defp gcolor8_rgba_float(red2, green2, blue2, alpha2) do
    red = gcolor8_channel_to_8bit(red2)
    green = gcolor8_channel_to_8bit(green2)
    blue = gcolor8_channel_to_8bit(blue2)
    alpha = Float.round(gcolor8_channel_to_8bit(alpha2) / 255.0, 2)
    "rgba(#{red}, #{green}, #{blue}, #{alpha})"
  end

  @spec gcolor8_channel_to_8bit(integer()) :: integer()
  defp gcolor8_channel_to_8bit(value) when is_integer(value), do: max(0, min(3, value)) * 85

  @spec hex_rgb(integer(), integer(), integer()) :: String.t()
  defp hex_rgb(red, green, blue)
       when is_integer(red) and is_integer(green) and is_integer(blue) do
    "#" <>
      (red |> Integer.to_string(16) |> String.pad_leading(2, "0")) <>
      (green |> Integer.to_string(16) |> String.pad_leading(2, "0")) <>
      (blue |> Integer.to_string(16) |> String.pad_leading(2, "0"))
  end
end
