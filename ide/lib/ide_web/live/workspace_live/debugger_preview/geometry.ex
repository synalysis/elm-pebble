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

  @trig_max_angle 65_536
  @pie_arc_steps 24

  @spec pie_sector_path(svg_op()) :: String.t()
  def pie_sector_path(op) when is_map(op) do
    op |> pie_sector_paths() |> Enum.join(" ")
  end

  def pie_sector_path(_), do: ""

  @spec pie_sector_paths(svg_op()) :: [String.t()]
  def pie_sector_paths(op) when is_map(op) do
    start_angle = op.start_angle || 0
    end_angle = op.end_angle || 0
    metrics = oval_metrics(op)

    angle_sectors(start_angle, end_angle)
    |> Enum.map(&single_pie_sector_path(metrics, &1.start, &1.end))
    |> Enum.reject(&(&1 == ""))
  end

  def pie_sector_paths(_), do: []

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
    value |> Ide.Emulator.GColor8.display_rgb() |> hex_rgb_from_tuple()
  end

  def pebble_color_to_svg(_value, fallback), do: fallback

  @spec angle_sectors(integer(), integer()) :: [%{start: integer(), end: integer()}]
  defp angle_sectors(start_angle, end_angle) do
    start = normalize_pebble_angle(start_angle)
    finish = normalize_pebble_angle(end_angle)

    cond do
      start == finish ->
        []

      end_angle >= @trig_max_angle ->
        [%{start: start, end: @trig_max_angle}]

      finish > start ->
        [%{start: start, end: finish}]

      true ->
        [%{start: start, end: @trig_max_angle}, %{start: 0, end: finish}]
    end
  end

  @spec normalize_pebble_angle(integer()) :: integer()
  defp normalize_pebble_angle(angle) when is_integer(angle) do
    rem(rem(angle, @trig_max_angle) + @trig_max_angle, @trig_max_angle)
  end

  @spec oval_metrics(svg_op()) :: %{cx: float(), cy: float(), rx: float(), ry: float()}
  defp oval_metrics(op) do
    x = op.x || 0
    y = op.y || 0
    w = max(op.w || 1, 1)
    h = max(op.h || 1, 1)

    %{
      cx: x + w / 2.0,
      cy: y + h / 2.0,
      rx: w / 2.0,
      ry: h / 2.0
    }
  end

  @spec single_pie_sector_path(%{cx: float(), cy: float(), rx: float(), ry: float()}, integer(), integer()) ::
          String.t()
  defp single_pie_sector_path(_metrics, _start, finish) when finish <= 0, do: ""

  defp single_pie_sector_path(_metrics, start_angle, end_angle) when end_angle <= start_angle,
    do: ""

  defp single_pie_sector_path(%{cx: cx, cy: cy, rx: rx, ry: ry}, start_angle, end_angle) do
    span = end_angle - start_angle

    arc_points =
      for step <- 0..@pie_arc_steps do
        angle = start_angle + div(span * step, @pie_arc_steps)
        point_on_oval(cx, cy, rx, ry, angle)
      end

    {sx, sy} = hd(arc_points)

    rest =
      arc_points
      |> tl()
      |> Enum.map_join(" ", fn {x, y} ->
        "L #{Float.round(x, 2)} #{Float.round(y, 2)}"
      end)

    "M #{Float.round(cx, 2)} #{Float.round(cy, 2)} L #{Float.round(sx, 2)} #{Float.round(sy, 2)} " <>
      rest <> " Z"
  end

  @spec point_on_oval(float(), float(), float(), float(), integer()) :: {float(), float()}
  defp point_on_oval(cx, cy, rx, ry, angle) do
    rad = pebble_angle_to_rad(angle)
    {cx + rx * :math.cos(rad), cy + ry * :math.sin(rad)}
  end

  @spec pebble_angle_to_rad(integer()) :: float()
  def pebble_angle_to_rad(angle) when is_integer(angle) do
    angle * 2.0 * :math.pi() / @trig_max_angle - :math.pi() / 2.0
  end

  def pebble_angle_to_rad(_), do: -:math.pi() / 2.0

  @spec argb8_to_svg(integer()) :: String.t()
  defp argb8_to_svg(argb) when is_integer(argb) do
    alpha = Bitwise.band(Bitwise.bsr(argb, 24), 0xFF)
    red = Bitwise.band(Bitwise.bsr(argb, 16), 0xFF)
    green = Bitwise.band(Bitwise.bsr(argb, 8), 0xFF)
    blue = Bitwise.band(argb, 0xFF)

    if alpha >= 255 do
      {red, green, blue} |> Ide.Emulator.SdkScreenshotStyle.correct_rgb_tuple() |> hex_rgb_from_tuple()
    else
      a = Float.round(alpha / 255.0, 2)
      {red, green, blue} = Ide.Emulator.SdkScreenshotStyle.correct_rgb_tuple({red, green, blue})
      "rgba(#{red}, #{green}, #{blue}, #{a})"
    end
  end

  @spec hex_rgb_from_tuple({integer(), integer(), integer()}) :: String.t()
  defp hex_rgb_from_tuple({red, green, blue}), do: hex_rgb(red, green, blue)

  @spec hex_rgb(integer(), integer(), integer()) :: String.t()
  defp hex_rgb(red, green, blue)
       when is_integer(red) and is_integer(green) and is_integer(blue) do
    "#" <>
      (red |> Integer.to_string(16) |> String.pad_leading(2, "0")) <>
      (green |> Integer.to_string(16) |> String.pad_leading(2, "0")) <>
      (blue |> Integer.to_string(16) |> String.pad_leading(2, "0"))
  end
end
