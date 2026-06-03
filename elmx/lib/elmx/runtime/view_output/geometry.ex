defmodule Elmx.Runtime.ViewOutput.Geometry do
  @moduledoc false

  def path_output_kind("pathFilled"), do: "path_filled"
  def path_output_kind("pathOutline"), do: "path_outline"
  def path_output_kind("pathOutlineOpen"), do: "path_outline_open"

  def path_fields(path) when is_map(path) do
    points =
      path
      |> Map.get("points", Map.get(path, :points, []))
      |> normalize_path_points_list()

    origin = Map.get(path, "origin") || Map.get(path, :origin) || %{}
    {offset_x, offset_y} = point_xy_map(origin)

    %{
      "points" => points,
      "offset_x" => offset_x,
      "offset_y" => offset_y,
      "rotation" => int_field(path, "rotation", 0)
    }
  end

  def path_fields(_), do: %{"points" => [], "offset_x" => 0, "offset_y" => 0, "rotation" => 0}

  def point_xy_map(%{"x" => x, "y" => y}) when is_integer(x) and is_integer(y), do: {x, y}
  def point_xy_map(%{x: x, y: y}) when is_integer(x) and is_integer(y), do: {x, y}
  def point_xy_map({x, y}) when is_integer(x) and is_integer(y), do: {x, y}
  def point_xy_map([x, y]) when is_integer(x) and is_integer(y), do: {x, y}
  def point_xy_map(_), do: {0, 0}

  def normalize_path_points_list(points) when is_list(points) do
    points
    |> Enum.map(&normalize_path_point/1)
    |> Enum.reject(&is_nil/1)
  end

  def normalize_path_points_list(_), do: []

  def normalize_path_point([x, y]) when is_integer(x) and is_integer(y), do: [x, y]
  def normalize_path_point({x, y}) when is_integer(x) and is_integer(y), do: [x, y]
  def normalize_path_point(%{"x" => x, "y" => y}) when is_integer(x) and is_integer(y), do: [x, y]
  def normalize_path_point(%{x: x, y: y}) when is_integer(x) and is_integer(y), do: [x, y]
  def normalize_path_point(_), do: nil
  def rect_fields(node, key) do
    bounds = Map.get(node, key) || Map.get(node, String.to_atom(key)) || %{}
    rect_bounds_from_value(bounds)
  end

  def rect_bounds_from_value(%{"x" => x, "y" => y, "w" => w, "h" => h}),
    do: {rect_int(x), rect_int(y), rect_int(w), rect_int(h)}

  def rect_bounds_from_value(%{x: x, y: y, w: w, h: h}),
    do: {rect_int(x), rect_int(y), rect_int(w), rect_int(h)}

  def rect_bounds_from_value({x, y, w, h}) when is_integer(x),
    do: {rect_int(x), rect_int(y), rect_int(w), rect_int(h)}

  def rect_bounds_from_value([x, y, w, h]) when is_integer(x),
    do: {rect_int(x), rect_int(y), rect_int(w), rect_int(h)}

  def rect_bounds_from_value(bounds) when is_map(bounds) do
    {x, y} = point_fields(bounds, "origin", {0, 0})
    w = int_field(bounds, "w", int_field(bounds, "width", 0))
    h = int_field(bounds, "h", int_field(bounds, "height", 0))
    {int_field(bounds, "x", x), int_field(bounds, "y", y), w, h}
  end

  def rect_bounds_from_value(_), do: {0, 0, 0, 0}

  def rect_int(value) when is_integer(value), do: value
  def rect_int(value) when is_float(value), do: trunc(value)
  def rect_int(_), do: 0

  def line_endpoints(node) when is_map(node) do
    x1 = int_field(node, "x1", nil)
    y1 = int_field(node, "y1", nil)
    x2 = int_field(node, "x2", nil)
    y2 = int_field(node, "y2", nil)

    if is_integer(x1) and is_integer(y1) and is_integer(x2) and is_integer(y2) do
      {x1, y1, x2, y2}
    else
      {fx, fy} = point_fields(node, "from")
      {tx, ty} = point_fields(node, "to")
      {fx, fy, tx, ty}
    end
  end

  def rect_bounds(node, nested_key) do
    x = int_field(node, "x", nil)
    y = int_field(node, "y", nil)
    w = int_field(node, "w", nil)
    h = int_field(node, "h", nil)

    if is_integer(x) and is_integer(y) and is_integer(w) and is_integer(h) do
      {x, y, w, h}
    else
      rect_fields(node, nested_key)
    end
  end

  def point_xy(node, nested_key, default \\ {0, 0}) do
    x = int_field(node, "x", nil)
    y = int_field(node, "y", nil)

    if is_integer(x) and is_integer(y) do
      {x, y}
    else
      point_fields(node, nested_key, default)
    end
  end

  def point_fields(node, key, default \\ {0, 0}) do
    point = Map.get(node, key) || Map.get(node, String.to_atom(key)) || %{}
    {int_field(point, "x", elem(default, 0)), int_field(point, "y", elem(default, 1))}
  end

  def text_content(node) when is_map(node) do
    value =
      Map.get(node, "text") || Map.get(node, :text) || Map.get(node, "label") ||
        Map.get(node, :label) || Map.get(node, "value") || Map.get(node, :value)

    to_string(value || "")
  end

  def label_display_text(node) when is_map(node) do
    text_content(node)
    |> case do
      "WaitingForCompanion" -> "Waiting for companion app"
      text -> text
    end
  end

  def text_align(node) do
    case Map.get(node, "text_align") || Map.get(node, :text_align) do
      value when is_binary(value) ->
        Elmx.Runtime.Pebble.TextOptions.fields(%{"alignment" => value}) |> elem(0)

      value when is_integer(value) ->
        Elmx.Runtime.Pebble.TextOptions.fields(%{"alignment" => value}) |> elem(0)

      _ ->
        node
        |> Map.get("options", Map.get(node, :options))
        |> then(fn options ->
          {align, _} = Elmx.Runtime.Pebble.TextOptions.fields(options)
          align
        end)
    end
  end

  def text_overflow(node) do
    case Map.get(node, "text_overflow") || Map.get(node, :text_overflow) do
      value when is_binary(value) ->
        Elmx.Runtime.Pebble.TextOptions.fields(%{"overflow" => value}) |> elem(1)

      value when is_integer(value) ->
        Elmx.Runtime.Pebble.TextOptions.fields(%{"overflow" => value}) |> elem(1)

      _ ->
        node
        |> Map.get("options", Map.get(node, :options))
        |> then(fn options ->
          {_, overflow} = Elmx.Runtime.Pebble.TextOptions.fields(options)
          overflow
        end)
    end
  end
  def sanitize_rect({x, y, w, h}, _node, opts) do
    screen_w = screen_dimension(opts, :screen_w)
    screen_h = screen_dimension(opts, :screen_h)

    w = max(w, 0)
    h = max(h, 0)

    {w, h} =
      if is_integer(screen_w) and screen_w > 0 and is_integer(screen_h) and screen_h > 0 do
        {
          min(w, max(0, screen_w - max(x, 0))),
          min(h, max(0, screen_h - max(y, 0)))
        }
      else
        {min(w, 512), min(h, 512)}
      end

    {x, y, w, h}
  end

  def screen_dimension(opts, key) when is_list(opts) do
    case Keyword.get(opts, key) do
      n when is_integer(n) and n > 0 ->
        n

      _ ->
        case Keyword.get(opts, :runtime_model) do
          %{} = model ->
            model
            |> Map.get(Atom.to_string(key))
            |> case do
              nil -> Map.get(model, screen_key_fallback(key))
              other -> other
            end
            |> case do
              n when is_integer(n) -> n
              n when is_float(n) -> trunc(n)
              _ -> nil
            end

          _ ->
            nil
        end
    end
  end

  def screen_key_fallback(:screen_w), do: "screenW"
  def screen_key_fallback(:screen_h), do: "screenH"

  @spec int_field(map(), String.t(), integer() | nil) :: integer() | nil
  def int_field(node, key, default) when is_map(node) do
    case Map.get(node, key) || Map.get(node, String.to_atom(key)) do
      value when is_integer(value) -> value
      value when is_float(value) -> trunc(value)
      _ -> default
    end
  end

end
