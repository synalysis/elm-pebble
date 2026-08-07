defmodule Ide.Debugger.TextParity do
  @moduledoc """
  Compare debugger SVG text ink bounding boxes to emulator PNG reference crops.

  Used by `mix ide.text_parity` and tagged regression tests under
  `test/fixtures/debugger_text_parity/`.
  """

  alias Ide.Png
  alias Ide.ProjectTemplatePreviews.Svg
  alias IdeWeb.WorkspaceLive.DebuggerPreview.{SvgOpNormalize, SvgStyle}

  @type bbox :: %{
          min_x: integer(),
          min_y: integer(),
          max_x: integer(),
          max_y: integer(),
          width: integer(),
          height: integer(),
          cx: float(),
          cy: float()
        }

  @type label_delta :: %{
          text: String.t(),
          box: map(),
          emulator: bbox() | nil,
          debugger: bbox() | nil,
          dx: float() | nil,
          dy: float() | nil,
          d_width: integer() | nil,
          d_height: integer() | nil,
          bottom_clipped?: boolean()
        }

  @type report :: %{
          fixture: String.t(),
          screen: %{width: pos_integer(), height: pos_integer()},
          labels: [label_delta()],
          mean_abs_dy: float(),
          mean_abs_dx: float(),
          max_abs_dy: float(),
          max_abs_dx: float(),
          mean_height_error: float(),
          any_bottom_clipped?: boolean()
        }

  @ink_luminance_floor 160
  @ink_chroma_max 48
  @ink_luminance_margin 24
  # Exact GRect only — padding pulled in adjacent dial ticks and inflated ink bboxes.
  @roi_pad 0

  @spec fixture_dir(String.t()) :: String.t()
  def fixture_dir(fixture_key) when is_binary(fixture_key) do
    Path.expand(
      Path.join(["..", "..", "..", "test", "fixtures", "debugger_text_parity", fixture_key]),
      __DIR__
    )
  end

  @spec compare_fixture(String.t()) :: {:ok, report()} | {:error, term()}
  def compare_fixture("yes"), do: compare_fixture("yes_emery")

  def compare_fixture(fixture_key) when is_binary(fixture_key) do
    with {:ok, fixture} <- load_fixture(fixture_key),
         {:ok, debugger_png} <- rasterize_debugger(fixture),
         {:ok, dbg_w, dbg_h, dbg_rgba} <- Png.load_rgba(debugger_png),
         true <- dbg_w == fixture.screen.width and dbg_h == fixture.screen.height do
      labels =
        Enum.map(fixture.labels, fn label ->
          box = Map.get(label, "box") || Map.get(label, :box) || %{}
          emu_bbox = ink_bbox(fixture.emulator_rgba, fixture.screen, box)
          dbg_bbox = ink_bbox(dbg_rgba, fixture.screen, box)
          delta_for_label(label, emu_bbox, dbg_bbox)
        end)

      {:ok, summarize_report(fixture_key, fixture.screen, labels)}
    else
      false ->
        {:error, :debugger_raster_size_mismatch}

      {:error, _} = error ->
        error
    end
  end

  @spec format_report(report()) :: String.t()
  def format_report(%{} = report) do
    header =
      "text parity #{report.fixture} (#{report.screen.width}x#{report.screen.height}) " <>
        "mean |dy|=#{Float.round(report.mean_abs_dy, 2)} max |dy|=#{Float.round(report.max_abs_dy * 1.0, 2)} " <>
        "mean |dx|=#{Float.round(report.mean_abs_dx, 2)} max |dx|=#{Float.round(report.max_abs_dx * 1.0, 2)} " <>
        "mean height err=#{Float.round(report.mean_height_error, 2)}" <>
        if(report.any_bottom_clipped?, do: " CLIPPED", else: "")

    rows =
      Enum.map(report.labels, fn row ->
        dy = row.dy |> format_delta()
        dx = row.dx |> format_delta()
        clip = if row.bottom_clipped?, do: " CLIP", else: ""

        "  #{String.pad_leading(row.text, 2)}  dy=#{dy}  dx=#{dx}  " <>
          "emu_h=#{bbox_height(row.emulator)} dbg_h=#{bbox_height(row.debugger)}#{clip}"
      end)

    ([header | rows] ++ [""]) |> Enum.join("\n")
  end

  @doc """
  Labels whose absolute vertical ink-centroid delta exceeds `max_abs_dy`.
  """
  @spec labels_exceeding_abs_dy(report(), number()) :: [label_delta()]
  def labels_exceeding_abs_dy(%{labels: labels}, max_abs_dy)
      when is_number(max_abs_dy) and max_abs_dy >= 0 do
    Enum.filter(labels, fn
      %{dy: dy} when is_number(dy) -> abs(dy) > max_abs_dy
      _ -> false
    end)
  end

  @spec load_fixture(String.t()) :: {:ok, fixture()} | {:error, term()}
  defp load_fixture(fixture_key) do
    dir = fixture_dir(fixture_key)

    with {:ok, labels_json} <- read_json(Path.join(dir, "labels.json")),
         {:ok, view_output} <- read_json(Path.join(dir, "runtime_view_output.json")),
         {:ok, width, height, emulator_rgba} <- Png.load_rgba(Path.join(dir, "emulator.png")) do
      screen = labels_json |> Map.get("screen", %{}) |> normalize_screen(width, height)

      {:ok,
       %{
         dir: dir,
         screen: screen,
         labels: Map.get(labels_json, "labels", []),
         runtime_view_output: view_output
       }
       |> Map.put(:emulator_rgba, emulator_rgba)}
    end
  end

  @type fixture :: %{
          dir: String.t(),
          screen: %{width: pos_integer(), height: pos_integer()},
          labels: [map()],
          runtime_view_output: [map()],
          emulator_rgba: binary()
        }

  @spec rasterize_debugger(fixture()) :: {:ok, binary()} | {:error, term()}
  defp rasterize_debugger(fixture) do
    # Text-only scene: hands / ticks / sun wedges that share dial label GRects
    # must not inflate debugger ink bboxes when we are measuring text placement.
    ops =
      fixture.runtime_view_output
      |> Enum.map(&SvgOpNormalize.normalize/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&text_parity_op?/1)
      |> then(fn ops ->
        [%{kind: :clear, color: 192} | Enum.reject(ops, &(&1.kind == :clear))]
      end)
      |> SvgStyle.apply_state()

    svg =
      Svg.document(ops, fixture.screen.width, fixture.screen.height,
        text_clips: true,
        svg_id: "text-parity"
      )

    rasterize_svg(svg, fixture.screen.width, fixture.screen.height)
  end

  defp text_parity_op?(%{kind: kind})
       when kind in [:clear, :text_label, :text_int, :text_color],
       do: true

  defp text_parity_op?(_op), do: false

  @spec rasterize_svg(String.t(), pos_integer(), pos_integer()) ::
          {:ok, binary()} | {:error, term()}
  defp rasterize_svg(svg, width, _height) do
    tmp_svg = Path.join(System.tmp_dir!(), "text-parity-#{System.unique_integer([:positive])}.svg")
    tmp_png = Path.join(System.tmp_dir!(), "text-parity-#{System.unique_integer([:positive])}.png")

    try do
      :ok = File.write!(tmp_svg, svg)

      case System.cmd("rsvg-convert", ["-w", Integer.to_string(width), "-o", tmp_png, tmp_svg],
             stderr_to_stdout: true
           ) do
        {_output, 0} ->
          File.read(tmp_png)

        {output, status} ->
          {:error, {:rsvg_convert_failed, status, output}}
      end
    after
      File.rm(tmp_svg)
      File.rm(tmp_png)
    end
  end

  @spec ink_bbox(binary(), %{width: pos_integer(), height: pos_integer()}, map()) :: bbox() | nil
  defp ink_bbox(rgba, screen, box) when is_binary(rgba) and is_map(box) do
    x = Map.get(box, "x") || Map.get(box, :x) || 0
    y = Map.get(box, "y") || Map.get(box, :y) || 0
    w = Map.get(box, "w") || Map.get(box, :w) || 0
    h = Map.get(box, "h") || Map.get(box, :h) || 0

    x0 = max(0, x - @roi_pad)
    # Outer dial labels share their GRect with the radial tick that enters from
    # the dial (toward the box top on every hour). Measure the lower band where
    # Gothic ink actually sits after top-of-rect draw + clip.
    y_slack = div(max(h, 0), 3)
    y0 = max(0, y + y_slack - @roi_pad)
    x1 = min(screen.width - 1, x + w - 1 + @roi_pad)
    y1 = min(screen.height - 1, y + h - 1 + @roi_pad)

    coords =
      ink_pixels(
        rgba,
        screen.width,
        x0,
        y0,
        x1,
        y1,
        @ink_luminance_floor,
        @ink_luminance_margin
      )

    case coords do
      [] ->
        nil

      _ ->
        case pick_glyph_ink(coords) do
          [] ->
            nil

          glyph ->
            xs = Enum.map(glyph, &elem(&1, 0))
            ys = Enum.map(glyph, &elem(&1, 1))
            min_x = Enum.min(xs)
            max_x = Enum.max(xs)
            min_y = Enum.min(ys)
            max_y = Enum.max(ys)
            n = length(glyph) * 1.0

            %{
              min_x: min_x,
              min_y: min_y,
              max_x: max_x,
              max_y: max_y,
              width: max_x - min_x + 1,
              height: max_y - min_y + 1,
              cx: Enum.sum(xs) / n,
              cy: Enum.sum(ys) / n
            }
        end
    end
  end

  # Dial label GRects often include the radial tick. Keep the largest blob that
  # looks like a glyph (not a 1px tick stroke).
  @spec pick_glyph_ink([{integer(), integer()}]) :: [{integer(), integer()}]
  defp pick_glyph_ink(coords) when is_list(coords) do
    components =
      coords
      |> connected_components()
      |> Enum.filter(fn component ->
        xs = Enum.map(component, &elem(&1, 0))
        ys = Enum.map(component, &elem(&1, 1))
        w = Enum.max(xs) - Enum.min(xs) + 1
        h = Enum.max(ys) - Enum.min(ys) + 1
        length(component) >= 8 and w >= 3 and h >= 3
      end)

    case components do
      [] -> densify_ink(coords)
      # Union multi-digit glyphs ("10"/"12") while dropping thin tick strokes.
      _ -> Enum.flat_map(components, & &1)
    end
  end

  @spec connected_components([{integer(), integer()}]) :: [[{integer(), integer()}]]
  defp connected_components(coords) when is_list(coords) do
    set = MapSet.new(coords)

    Enum.reduce(coords, {[], MapSet.new()}, fn point, {components, visited} ->
      if MapSet.member?(visited, point) do
        {components, visited}
      else
        {component, visited} = flood_fill(point, set, visited)
        {[component | components], visited}
      end
    end)
    |> elem(0)
  end

  defp flood_fill(start, set, visited) do
    flood_fill([start], set, visited, [])
  end

  defp flood_fill([], _set, visited, acc), do: {acc, visited}

  defp flood_fill([point | rest], set, visited, acc) do
    if MapSet.member?(visited, point) or not MapSet.member?(set, point) do
      flood_fill(rest, set, visited, acc)
    else
      {x, y} = point
      neighbors = for dy <- -1..1, dx <- -1..1, dx != 0 or dy != 0, do: {x + dx, y + dy}
      flood_fill(neighbors ++ rest, set, MapSet.put(visited, point), [point | acc])
    end
  end

  # Drop thin tick strokes that share dial-label GRects; keep denser glyph ink.
  @spec densify_ink([{integer(), integer()}]) :: [{integer(), integer()}]
  defp densify_ink(coords) when is_list(coords) do
    set = MapSet.new(coords)

    dense =
      Enum.filter(coords, fn {x, y} ->
        neighbor_count =
          Enum.reduce(-1..1, 0, fn dy, acc ->
            Enum.reduce(-1..1, acc, fn dx, inner ->
              if (dx != 0 or dy != 0) and MapSet.member?(set, {x + dx, y + dy}) do
                inner + 1
              else
                inner
              end
            end)
          end)

        neighbor_count >= 3
      end)

    if dense == [], do: coords, else: dense
  end

  @spec ink_pixels(
          binary(),
          pos_integer(),
          integer(),
          integer(),
          integer(),
          integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: [{integer(), integer()}]
  defp ink_pixels(rgba, width, x0, y0, x1, y1, floor, margin) do
    samples =
      for py <- y0..y1,
          px <- x0..x1,
          do: {px, py, pixel_rgba(rgba, width, px, py)}

    lums =
      Enum.map(samples, fn {px, py, {r, g, b, _}} ->
        {px, py, luminance_rgb(r, g, b), chroma_rgb(r, g, b)}
      end)

    sorted = lums |> Enum.map(&elem(&1, 2)) |> Enum.sort()
    background = percentile(sorted, 0.10)
    threshold = max(floor, background + margin)

    # Prefer achromatic bright pixels (white Gothic / AA sans). This drops the
    # chrome-yellow sun wedge that otherwise fills whole label GRects.
    for {px, py, lum, chroma} <- lums,
        lum >= threshold and chroma <= @ink_chroma_max,
        do: {px, py}
  end

  defp chroma_rgb(r, g, b), do: max(r, max(g, b)) - min(r, min(g, b))

  @spec pixel_rgba(binary(), pos_integer(), integer(), integer()) ::
          {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}
  defp pixel_rgba(rgba, width, x, y) do
    offset = (y * width + x) * 4
    <<r, g, b, a>> = :binary.part(rgba, offset, 4)
    {r, g, b, a}
  end

  @spec luminance_rgb(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  defp luminance_rgb(r, g, b), do: div(r * 299 + g * 587 + b * 114, 1000)

  @spec percentile([number()], float()) :: number()
  defp percentile([], _ratio), do: 0

  defp percentile(sorted, ratio) when is_list(sorted) and is_float(ratio) do
    count = length(sorted)

    cond do
      count == 0 ->
        0

      count == 1 ->
        hd(sorted)

      true ->
        index = min(count - 1, max(0, round(ratio * (count - 1))))
        Enum.at(sorted, index)
    end
  end

  @spec delta_for_label(map(), bbox() | nil, bbox() | nil) :: label_delta()
  defp delta_for_label(label, emu_bbox, dbg_bbox) do
    box = Map.get(label, "box") || Map.get(label, :box) || %{}
    text = to_string(Map.get(label, "text") || Map.get(label, :text) || "")

    {dx, dy, d_width, d_height} =
      case {emu_bbox, dbg_bbox} do
        {%{} = emu, %{} = dbg} ->
          {dbg.cx - emu.cx, dbg.cy - emu.cy, dbg.width - emu.width, dbg.height - emu.height}

        _ ->
          {nil, nil, nil, nil}
      end

    bottom_clipped? =
      case dbg_bbox do
        %{} = dbg ->
          box_bottom = (Map.get(box, "y") || Map.get(box, :y) || 0) +
                         (Map.get(box, "h") || Map.get(box, :h) || 0) - 1

          dbg.max_y > box_bottom

        _ ->
          false
      end

    %{
      text: text,
      box: box,
      emulator: emu_bbox,
      debugger: dbg_bbox,
      dx: dx,
      dy: dy,
      d_width: d_width,
      d_height: d_height,
      bottom_clipped?: bottom_clipped?
    }
  end

  @spec summarize_report(String.t(), map(), [label_delta()]) :: report()
  defp summarize_report(fixture_key, screen, labels) do
    dy_values = labels |> Enum.map(& &1.dy) |> Enum.reject(&is_nil/1)
    dx_values = labels |> Enum.map(& &1.dx) |> Enum.reject(&is_nil/1)

    height_errors =
      labels
      |> Enum.flat_map(fn row ->
        case {row.emulator, row.debugger} do
          {%{height: eh}, %{height: dh}} -> [abs(dh - eh)]
          _ -> []
        end
      end)

    %{
      fixture: fixture_key,
      screen: screen,
      labels: labels,
      mean_abs_dy: mean_abs(dy_values),
      mean_abs_dx: mean_abs(dx_values),
      max_abs_dy: max_abs(dy_values),
      max_abs_dx: max_abs(dx_values),
      mean_height_error:
        if(height_errors == [], do: 0.0, else: Enum.sum(height_errors) / length(height_errors)),
      any_bottom_clipped?: Enum.any?(labels, & &1.bottom_clipped?)
    }
  end

  @spec max_abs([number()]) :: float()
  defp max_abs([]), do: 0.0
  defp max_abs(values), do: values |> Enum.map(&abs/1) |> Enum.max() |> Kernel.*(1.0)

  @spec mean_abs([number()]) :: float()
  defp mean_abs([]), do: 0.0

  defp mean_abs(values) do
    values |> Enum.map(&abs/1) |> Enum.sum() |> Kernel./(length(values))
  end

  @spec bbox_height(bbox() | nil) :: String.t()
  defp bbox_height(nil), do: "-"
  defp bbox_height(%{height: height}), do: Integer.to_string(height)

  @spec format_delta(number() | nil) :: String.t()
  defp format_delta(nil), do: "  -"

  defp format_delta(value) when is_number(value) do
    rounded = Float.round(value * 1.0, 1)
    sign = if rounded >= 0, do: "+", else: ""
    (sign <> :erlang.float_to_binary(rounded, decimals: 1)) |> String.pad_leading(5)
  end

  @spec normalize_screen(map(), pos_integer(), pos_integer()) :: %{
          width: pos_integer(),
          height: pos_integer()
        }
  defp normalize_screen(screen, width, height) do
    %{
      width: Map.get(screen, "width") || Map.get(screen, :width) || width,
      height: Map.get(screen, "height") || Map.get(screen, :height) || height
    }
  end

  @spec read_json(String.t()) :: {:ok, term()} | {:error, term()}
  defp read_json(path) do
    with {:ok, bytes} <- File.read(path) do
      Jason.decode(bytes)
    end
  end
end
