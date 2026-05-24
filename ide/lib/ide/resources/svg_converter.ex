defmodule Ide.Resources.SvgConverter do
  @moduledoc """
  Converts compatible SVG files to Pebble Draw Command (PDC) binaries.

  Supports hex colors (`#RRGGBB`), CSS and Pebble color names (`black`,
  `vividCerulean`, `blueMoon`, etc.), and the SVG elements used by Pebble's
  vector toolchain: `path`, `rect`, `circle`, `line`, `polyline`, `polygon`,
  and nested `g` groups.
  """

  alias Ide.Resources.{ConversionReport, PdcDecoder, PdcEncoder, PebbleColor, SvgPath}

  defmodule ConversionResult do
    @moduledoc false

    alias Ide.Resources.ConversionReport

    @type t :: %__MODULE__{
            bytes: binary(),
            report: ConversionReport.t()
          }

    defstruct [:bytes, :report]
  end

  @supported_tags ~w(path rect circle line polyline polygon)

  @type convert_error ::
          :svg_conversion_failed
          | :invalid_pdc_output
          | :unsupported_svg
          | File.posix()

  @spec convert_svg_to_pdc(Path.t(), Path.t(), keyword()) :: :ok | {:error, convert_error()}
  def convert_svg_to_pdc(svg_path, pdc_path, opts \\ [])
      when is_binary(svg_path) and is_binary(pdc_path) do
    with {:ok, svg} <- File.read(svg_path),
         {:ok, result} <- convert(svg, opts),
         :ok <- File.mkdir_p(Path.dirname(pdc_path)),
         :ok <- File.write(pdc_path, result.bytes),
         :ok <- validate_pdc_bytes(result.bytes) do
      :ok
    else
      {:error, :invalid_image} -> {:error, :svg_conversion_failed}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec convert_svg_string(String.t(), keyword()) :: {:ok, ConversionResult.t()} | {:error, convert_error()}
  def convert_svg_string(svg, opts \\ []) when is_binary(svg), do: convert(svg, opts)

  @spec convert(String.t(), keyword()) :: {:ok, ConversionResult.t()} | {:error, convert_error()}
  def convert(svg, opts \\ []) when is_binary(svg) do
    opts = normalize_opts(opts)
    report = ConversionReport.new()

    with {:ok, document} <- Floki.parse_document(svg),
         [root | _] <- Floki.find(document, "svg") do
      {translate, {width, height}} = viewbox_info(root)
      ctx = build_context(translate, opts, report)

      {commands, report} =
        root
        |> collect_commands(ctx)
        |> then(fn {cmds, rpt} -> {Enum.reverse(cmds), rpt} end)

      report =
        ConversionReport.stats(report, %{
          commands: length(commands),
          width: round(width),
          height: round(height)
        })

      cond do
        commands == [] and opts[:strict] ->
          {:error, :svg_conversion_failed}

        true ->
          image = %{width: round(width), height: round(height), commands: commands}

          case PdcEncoder.encode(image) do
            {:ok, bytes} ->
              {:ok, %ConversionResult{bytes: bytes, report: report}}

            error ->
              error
          end
      end
    else
      _ -> {:error, :svg_conversion_failed}
    end
  end

  @spec convert_svg_sequence([String.t()], keyword()) ::
          {:ok, ConversionResult.t()} | {:error, convert_error()}
  def convert_svg_sequence(svgs, opts \\ []) when is_list(svgs) do
    opts = normalize_opts(opts)

    with {:ok, frames, report} <- convert_frames(svgs, opts) do
      case PdcEncoder.encode_sequence(frames,
             frame_duration_ms: opts[:frame_duration_ms],
             play_count: opts[:play_count]
           ) do
        {:ok, bytes} ->
          {:ok, %ConversionResult{bytes: bytes, report: report}}

        error ->
          error
      end
    end
  end

  defp convert_frames(svgs, opts) do
    Enum.reduce_while(svgs, {:ok, [], ConversionReport.new()}, fn svg, {:ok, frames, report} ->
      case convert(svg, opts) do
        {:ok, %{bytes: bytes, report: frame_report}} ->
          case PdcDecoder.decode(bytes) do
            {:ok, image} ->
              {:cont, {:ok, frames ++ [image], merge_reports(report, frame_report)}}

            {:error, _} ->
              {:halt, {:error, :svg_conversion_failed}}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp merge_reports(left, right) do
    report =
      Enum.reduce(right.warnings, left, fn w, acc ->
        ConversionReport.warn(acc, w.code, w.element, w.detail)
      end)

    Enum.reduce(right.unsupported, report, fn u, acc ->
      ConversionReport.unsupported(acc, u.tag, u.reason)
    end)
  end

  defp normalize_opts(opts) do
    [
      precise: Keyword.get(opts, :precise, false),
      color_mode: Keyword.get(opts, :color_mode, :truncate),
      flatten_curves: Keyword.get(opts, :flatten_curves, false),
      flatten_tolerance: Keyword.get(opts, :flatten_tolerance, 0.5),
      frame_duration_ms: Keyword.get(opts, :frame_duration_ms, 100),
      play_count: Keyword.get(opts, :play_count, 1),
      strict: Keyword.get(opts, :strict, false)
    ]
  end

  defp build_context(translate, opts, report) do
    %{
      translate: translate,
      style: group_style(%{}),
      current_color: nil,
      opts: opts,
      report: report,
      defs: %{}
    }
  end

  @spec validate_pdc_bytes(binary()) :: :ok | {:error, :invalid_pdc_output}
  def validate_pdc_bytes(bytes) when is_binary(bytes) and byte_size(bytes) >= 8 do
    case bytes do
      <<magic::binary-size(4), _size::32, _rest::binary>> when magic in ["PDCI", "PDCS"] ->
        :ok

      _ ->
        {:error, :invalid_pdc_output}
    end
  end

  def validate_pdc_bytes(_), do: {:error, :invalid_pdc_output}

  @spec pdc_magic(binary()) :: String.t() | nil
  def pdc_magic(bytes) when is_binary(bytes) and byte_size(bytes) >= 4 do
    <<magic::binary-size(4), _rest::binary>> = bytes
    magic
  end

  def pdc_magic(_), do: nil

  defp collect_commands(node, ctx) do
    node
    |> Floki.children()
    |> Enum.reduce({[], ctx.report}, fn child, {cmds, report} ->
      child_ctx = %{ctx | report: report}

      case collect_node_commands(child, child_ctx) do
        {new_cmds, new_report} -> {cmds ++ new_cmds, new_report}
      end
    end)
  end

  defp collect_node_commands({"symbol", attrs, children}, ctx) do
    collect_node_commands({"g", attrs, children}, ctx)
  end

  defp collect_node_commands({"defs", _attrs, children}, ctx) do
    defs =
      children
      |> Enum.filter(fn {tag, _, _} -> tag == "symbol" end)
      |> Map.new(fn {_tag, attrs, sub} -> {attr_list(attrs, "id"), {"symbol", attrs, sub}} end)

    collect_commands({"svg", [], children}, %{ctx | defs: Map.merge(ctx.defs, defs)})
  end

  defp collect_node_commands({"g", attrs, children}, ctx) do
    if hidden?(attrs) do
      {[], ctx.report}
    else
      child_style = merge_group_style(ctx.style, attrs)
      child_translate = add_translate(ctx.translate, attrs)

      child_ctx = %{
        ctx
        | translate: child_translate,
          style: child_style,
          current_color: current_color_value(child_style, attrs, ctx.current_color)
      }

      Enum.reduce(children, {[], ctx.report}, fn child, {cmds, report} ->
        case collect_node_commands(child, %{child_ctx | report: report}) do
          {new_cmds, new_report} -> {cmds ++ new_cmds, new_report}
        end
      end)
    end
  end

  defp collect_node_commands({"layer", attrs, children}, ctx) do
    if hidden?(attrs) do
      {[], ctx.report}
    else
      layer_translate = layer_translate_offset(attrs)
      child_translate = {elem(ctx.translate, 0) + elem(layer_translate, 0), elem(ctx.translate, 1) + elem(layer_translate, 1)}
      collect_node_commands({"g", attrs, children}, %{ctx | translate: child_translate})
    end
  end

  defp collect_node_commands({"use", attrs, _children}, ctx) do
    with href when is_binary(href) <- attr_list(attrs, "href") || attr_list(attrs, "xlink:href"),
         id <- String.trim_leading(href, "#"),
         {tag, sym_attrs, sym_children} <- Map.get(ctx.defs, id) do
      merged = merge_use_attrs(sym_attrs, attrs)
      collect_node_commands({tag, merged, sym_children}, ctx)
    else
      _ -> {[], ConversionReport.unsupported(ctx.report, "use", :missing_symbol)}
    end
  end

  defp collect_node_commands({tag, attrs, _children}, ctx) when tag in @supported_tags do
    if hidden?(attrs) do
      {[], ctx.report}
    else
      case build_command(tag, attrs, ctx) do
        nil -> {[], ctx.report}
        command -> {[command], ctx.report}
      end
    end
  end

  defp collect_node_commands({"svg", _attrs, children}, ctx) do
    Enum.reduce(children, {[], ctx.report}, fn child, {cmds, report} ->
      case collect_node_commands(child, %{ctx | report: report}) do
        {new_cmds, new_report} -> {cmds ++ new_cmds, new_report}
      end
    end)
  end

  defp collect_node_commands({tag, _attrs, _children}, ctx) do
    {[], ConversionReport.unsupported(ctx.report, to_string(tag), :unsupported_element)}
  end

  defp build_command(tag, attrs, ctx) do
    attrs = merge_style(attrs)
    style = ctx.style
    precise = ctx.opts[:precise]
    color_opts = [color_mode: ctx.opts[:color_mode]]

    opacity = calc_opacity(style_opacity(style, attrs))
    stroke = resolve_color(style_value(style, attrs, "stroke"), ctx.current_color)
    fill = resolve_color(style_value(style, attrs, "fill"), ctx.current_color)
    stroke_opacity = calc_opacity(style_value(style, attrs, "stroke-opacity"))
    fill_opacity = calc_opacity(style_value(style, attrs, "fill-opacity"))

    stroke_color = PebbleColor.parse(stroke, calc_opacity(stroke_opacity, opacity), color_opts)
    fill_color = PebbleColor.parse(fill, calc_opacity(fill_opacity, opacity), color_opts)
    stroke_width = stroke_width(style, attrs, stroke_color)

    if stroke_color == 0 and fill_color == 0 do
      nil
    else
      {stroke_color, stroke_width} = normalize_stroke(stroke_color, stroke_width)

      with {:ok, command} <-
             shape_command(tag, attrs, ctx.translate, precise, stroke_color, stroke_width, fill_color, ctx.opts) do
        command
      else
        _ -> nil
      end
    end
  end

  defp shape_command("path", attrs, translate, precise, stroke_color, stroke_width, fill_color, opts) do
    path_opts = [
      flatten_curves: opts[:flatten_curves],
      flatten_tolerance: opts[:flatten_tolerance]
    ]

    case attr(attrs, "d") do
      nil ->
        :error

      path_data ->
        case SvgPath.points(path_data, path_opts) do
          {:ok, points, open?} ->
            {:ok,
             %{
               kind: :path,
               open: open?,
               stroke_color: stroke_color,
               stroke_width: stroke_width,
               fill_color: fill_color,
               points: pebble_points(points, translate, precise),
               radius: nil,
               precise: precise
             }}

          :error ->
            :error
        end
    end
  end

  defp shape_command("polygon", attrs, translate, precise, stroke_color, stroke_width, fill_color, _opts) do
    points = points_from_attr(attrs)

    if points == [] do
      :error
    else
      {:ok, path_command(points, false, translate, precise, stroke_color, stroke_width, fill_color)}
    end
  end

  defp shape_command("polyline", attrs, translate, precise, stroke_color, stroke_width, fill_color, _opts) do
    points = points_from_attr(attrs)

    if points == [] do
      :error
    else
      {:ok, path_command(points, true, translate, precise, stroke_color, stroke_width, fill_color)}
    end
  end

  defp shape_command("line", attrs, translate, precise, stroke_color, stroke_width, fill_color, _opts) do
    with {x1, ""} <- float_attr(attrs, "x1"),
         {y1, ""} <- float_attr(attrs, "y1"),
         {x2, ""} <- float_attr(attrs, "x2"),
         {y2, ""} <- float_attr(attrs, "y2") do
      {:ok,
       path_command([{x1, y1}, {x2, y2}], true, translate, precise, stroke_color, stroke_width, fill_color)}
    else
      _ -> :error
    end
  end

  defp shape_command("rect", attrs, translate, precise, stroke_color, stroke_width, fill_color, _opts) do
    with {x, ""} <- float_attr(attrs, "x", "0"),
         {y, ""} <- float_attr(attrs, "y", "0"),
         {w, ""} <- float_attr(attrs, "width"),
         {h, ""} <- float_attr(attrs, "height") do
      points = [{x, y}, {x + w, y}, {x + w, y + h}, {x, y + h}]

      {:ok,
       path_command(points, false, translate, precise, stroke_color, stroke_width, fill_color)}
    else
      _ -> :error
    end
  end

  defp shape_command("circle", attrs, translate, _precise, stroke_color, stroke_width, fill_color, _opts) do
    with {cx, ""} <- float_attr(attrs, "cx"),
         {cy, ""} <- float_attr(attrs, "cy"),
         {radius, ""} <- float_attr(attrs, "r", attr(attrs, "z")) do
      [point] = pebble_points([{cx, cy}], translate, false)

      {:ok,
       %{
         kind: :circle,
         open: false,
         stroke_color: stroke_color,
         stroke_width: stroke_width,
         fill_color: fill_color,
         points: [point],
         radius: round(radius),
         precise: false
       }}
    else
      _ -> :error
    end
  end

  defp shape_command(_tag, _attrs, _translate, _precise, _stroke, _width, _fill, _opts), do: :error

  defp hidden?(attrs) do
    String.downcase(to_string(attr_list(attrs, "display") || "")) == "none"
  end

  defp resolve_color("currentColor", current) when is_binary(current), do: current
  defp resolve_color(color, _current), do: color

  defp current_color_value(style, attrs, inherited) do
    style_value(style, attrs, "color") || inherited
  end

  defp layer_translate_offset(attrs) do
    case attr_list(attrs, "translate") do
      nil ->
        {0, 0}

      value ->
        case Regex.run(~r/translate\(([-\d.]+)[,\s]+([-\d.]+)\)/, value) do
          [_, x, y] -> {parse_float(x), parse_float(y)}
          _ -> {0, 0}
        end
    end
  end

  defp merge_use_attrs(sym_attrs, use_attrs) do
    sym = Map.new(flatten_attrs(sym_attrs))
    use = Map.new(flatten_attrs(use_attrs))
    x = parse_float(attr_list(use_attrs, "x") || "0")
    y = parse_float(attr_list(use_attrs, "y") || "0")

    transform =
      case attr_list(use_attrs, "transform") do
        nil -> "translate(#{x},#{y})"
        existing -> existing <> " translate(#{x},#{y})"
      end

    Map.merge(sym, use) |> Map.put("transform", transform)
  end

  defp path_command(points, open?, translate, precise, stroke_color, stroke_width, fill_color) do
    %{
      kind: :path,
      open: open?,
      stroke_color: stroke_color,
      stroke_width: stroke_width,
      fill_color: fill_color,
      points: pebble_points(points, translate, precise),
      radius: nil,
      precise: precise
    }
  end

  defp pebble_points(points, translate, precise) do
    Enum.map(points, fn point ->
      point
      |> sum_points(translate)
      |> to_pebble_coord(precise)
    end)
  end

  defp to_pebble_coord({x, y}, precise) do
    {x, y} = {x - 0.5, y - 0.5}
    {x, y} = if precise, do: {x * 8, y * 8}, else: {x, y}
    %{x: python_round(x), y: python_round(y)}
  end

  defp python_round(value) do
    value
    |> Kernel.+(1.0e-10)
    |> round()
  end

  defp sum_points({x, y}, {tx, ty}), do: {x + tx, y + ty}

  defp points_from_attr(attrs) do
    case attr(attrs, "points") do
      nil ->
        []

      point_str ->
        point_str
        |> String.split(~r/\s+/, trim: true)
        |> Enum.map(fn pair ->
          case String.split(pair, ",") do
            [x, y] -> {parse_float(x), parse_float(y)}
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
    end
  end

  defp viewbox_info({"svg", attrs, _children}) do
    case attr(attrs, "viewBox") do
      nil ->
        width = attr_float(attrs, "width", 0)
        height = attr_float(attrs, "height", 0)
        {{0, 0}, {width, height}}

      viewbox ->
        case String.split(viewbox, ~r/\s+/, trim: true) do
          [min_x, min_y, width, height] ->
            {{-parse_float(min_x), -parse_float(min_y)},
             {parse_float(width), parse_float(height)}}

          _ ->
            {{0, 0}, {0, 0}}
        end
    end
  end

  defp add_translate({x, y}, attrs) do
    {x, y}
    |> apply_transform(attr_list(attrs, "transform"))
    |> apply_transform(attr_list(attrs, "translate") && "translate(#{attr_list(attrs, "translate")})")
  end

  defp apply_transform({x, y}, nil), do: {x, y}

  defp apply_transform({x, y}, transform) when is_binary(transform) do
    case transform_translate(transform) do
      {tx, ty} -> {x + tx, y + ty}
      _ -> {x, y}
    end
  end

  defp transform_translate(transform) when is_binary(transform) do
    case Regex.run(~r/translate\(([-\d.]+)[,\s]+([-\d.]+)\)/, transform) do
      [_, x, y] -> {parse_float(x), parse_float(y)}
      _ -> nil
    end
  end

  defp group_style(style) do
    Map.merge(
      %{
        "opacity" => nil,
        "fill" => nil,
        "fill-opacity" => nil,
        "stroke" => nil,
        "stroke-opacity" => nil,
        "stroke-width" => nil
      },
      style
    )
  end

  defp merge_group_style(style, attrs) do
    attrs = if is_list(attrs), do: Map.new(attrs), else: attrs

    style
    |> Map.merge(
      Map.take(attrs, [
        "opacity",
        "fill",
        "fill-opacity",
        "stroke",
        "stroke-opacity",
        "stroke-width"
      ])
    )
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp merge_style(attrs) do
    attrs = Map.new(flatten_attrs(attrs))

    case Map.get(attrs, "style") do
      nil ->
        attrs

      style ->
        style_attrs =
          style
          |> String.split(";")
          |> Enum.map(&String.split(&1, ":", parts: 2))
          |> Enum.filter(fn parts -> length(parts) == 2 end)
          |> Map.new(fn [key, value] -> {String.trim(key), String.trim(value)} end)

        Map.merge(style_attrs, Map.delete(attrs, "style"))
    end
  end

  defp flatten_attrs(attrs) when is_list(attrs), do: attrs
  defp flatten_attrs(attrs) when is_map(attrs), do: Enum.to_list(attrs)

  defp style_value(style, attrs, key) do
    Map.get(attrs, key) || Map.get(style, key) || attr_list(attrs, key)
  end

  defp style_opacity(style, attrs) do
    style_value(style, attrs, "opacity")
  end

  defp stroke_width(style, attrs, stroke_color) do
    if stroke_color == 0 do
      0
    else
      case style_value(style, attrs, "stroke-width") do
        nil -> 1
        value -> parse_width(value)
      end
    end
  end

  defp parse_width(value) do
    value =
      value
      |> to_string()
      |> String.trim()
      |> String.replace("px", "")

    case Float.parse(value) do
      {number, _} ->
        width = trunc(number)
        if width >= 1, do: width, else: 1

      :error ->
        0
    end
  end

  defp normalize_stroke(stroke_color, stroke_width) do
    cond do
      stroke_color == 0 -> {0, 0}
      stroke_width == 0 -> {0, 0}
      true -> {stroke_color, stroke_width}
    end
  end

  defp calc_opacity(nil), do: 1.0
  defp calc_opacity(value) when is_binary(value), do: calc_opacity(parse_float(value))
  defp calc_opacity(value) when is_number(value), do: max(min(value * 1.0, 1.0), 0.0)

  defp calc_opacity(a, b) do
    calc_opacity(a) * calc_opacity(b)
  end

  defp parse_float(value) do
    case Float.parse(to_string(value)) do
      {number, _} -> number
      :error -> 1.0
    end
  end

  defp attr_list(attrs, key, default \\ nil)

  defp attr_list(attrs, key, default) when is_list(attrs), do: attr(attrs, key, default)
  defp attr_list(attrs, key, default) when is_map(attrs), do: Map.get(attrs, key, default)
  defp attr_list(_attrs, _key, default), do: default

  defp attr(attrs, key, default \\ nil) do
    key_down = String.downcase(key)

    Enum.find_value(flatten_attrs(attrs), default, fn {name, value} ->
      if String.downcase(to_string(name)) == key_down, do: value
    end)
  end

  defp float_attr(attrs, key, default \\ nil) do
    case attr(attrs, key, default) do
      nil -> :error
      value -> Float.parse(to_string(value))
    end
  end

  defp attr_float(attrs, key, default) do
    case float_attr(attrs, key, to_string(default)) do
      {value, _} -> value
      :error -> default * 1.0
    end
  end
end
