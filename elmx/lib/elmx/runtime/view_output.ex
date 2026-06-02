defmodule Elmx.Runtime.ViewOutput do
  @moduledoc """
  Flattens evaluated `Pebble.Ui` view trees into debugger `runtime_view_output` rows.
  """

  @draw_types ~w(
    clear fillRect rect roundRect line circle fillCircle pixel
    drawVectorAt drawVectorSequenceAt drawBitmapInRect drawBitmapSequenceAt
    drawRotatedBitmap arc fillRadial text textLabel textInt
    path pathFilled pathOutline pathOutlineOpen
  )

  @type opts :: keyword()

  @spec from_view_tree(term(), opts()) :: [map()]
  def from_view_tree(tree, opts \\ []) do
    tree
    |> List.wrap()
    |> Enum.flat_map(&flatten_node(&1, opts))
    |> apply_resource_indices(opts)
  end

  @doc """
  Resolves `vector_id` / `animation_id` on flattened rows using optional resource index maps.
  """
  @spec apply_resource_indices([map()], opts()) :: [map()]
  def apply_resource_indices(rows, opts \\ []) when is_list(rows) do
    vector_indices = vector_resource_indices(opts)
    bitmap_indices = bitmap_resource_indices(opts)
    animation_indices = animation_resource_indices(opts)

    Enum.map(rows, fn row ->
      row
      |> apply_vector_resource_index(vector_indices)
      |> apply_bitmap_resource_index(bitmap_indices)
      |> apply_animation_resource_index(animation_indices)
    end)
  end

  defp flatten_node(%{type: type} = node, opts) when is_binary(type) or is_atom(type) do
    type = to_string(type)

    cond do
      type in ["windowStack", "WindowStack"] ->
        children(node) |> Enum.flat_map(&flatten_node(&1, opts))

      type in ["window", "Window", "WindowNode"] ->
        children(node) |> Enum.flat_map(&flatten_node(&1, opts))

      type in ["canvasLayer", "CanvasLayer"] ->
        children(node)
        |> Enum.reject(&expr_placeholder?/1)
        |> Enum.flat_map(&flatten_node(&1, opts))

      type == "group" ->
        style_rows(node) ++ (children(node) |> Enum.flat_map(&flatten_node(&1, opts)))

      type in @draw_types ->
        case draw_row(node, opts) do
          nil -> []
          row -> [row]
        end

      true ->
        children(node) |> Enum.flat_map(&flatten_node(&1, opts))
    end
  end

  defp flatten_node(%{"type" => type} = node, opts) when is_binary(type),
    do: flatten_node(Map.put_new(node, :type, type), opts)

  defp flatten_node(_node, _opts), do: []

  defp expr_placeholder?(%{"type" => "expr"}), do: true
  defp expr_placeholder?(%{type: "expr"}), do: true
  defp expr_placeholder?(_), do: false

  defp children(node) when is_map(node) do
    case Map.get(node, "children") || Map.get(node, :children) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp style_rows(%{style: style}) when is_map(style), do: style_rows(style)
  defp style_rows(%{"style" => style}) when is_map(style), do: style_rows(style)

  defp style_rows(style) when is_map(style) do
    [
      style_row(style, "stroke_color"),
      style_row(style, "fill_color"),
      style_row(style, "text_color")
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp style_rows(_), do: []

  defp style_row(style, key) when is_map(style) and is_binary(key) do
    value = Map.get(style, key) || Map.get(style, String.to_atom(key))

    if is_integer(value) do
      %{"kind" => key, "color" => value}
    end
  end

  defp draw_row(node, opts) when is_map(node),
    do: node |> normalize_node_type() |> do_draw_row(opts)

  defp normalize_node_type(node) when is_map(node) do
    type =
      node
      |> Map.get("type", Map.get(node, :type))
      |> to_string()

    node
    |> Map.new(fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
    |> Map.put("type", type)
  end

  defp do_draw_row(%{"type" => "clear"} = node, _opts),
    do: %{"kind" => "clear", "color" => int_field(node, "color", 0xC0)}

  defp do_draw_row(%{"type" => "fillRect"} = node, opts) do
    {x, y, w, h} = rect_fields(node, "bounds") |> sanitize_rect(node, opts)

    %{
      "kind" => "fill_rect",
      "x" => x,
      "y" => y,
      "w" => w,
      "h" => h,
      "fill" => int_field(node, "color", 0)
    }
  end

  defp do_draw_row(%{"type" => "drawBitmapInRect"} = node, opts) do
    {x, y, w, h} = rect_fields(node, "bounds") |> sanitize_rect(node, opts)
    resource = Map.get(node, "resource") || Map.get(node, :resource)
    indices = bitmap_resource_indices(opts)

    %{
      "kind" => "bitmap_in_rect",
      "resource" => resource_name(resource),
      "bitmap_id" => resource_bitmap_id(resource, indices),
      "x" => x,
      "y" => y,
      "w" => w,
      "h" => h
    }
  end

  defp do_draw_row(%{"type" => "drawBitmapSequenceAt"} = node, opts) do
    {x, y} = point_xy(node, "origin")
    resource = Map.get(node, "resource") || Map.get(node, :resource)
    indices = animation_resource_indices(opts)

    %{
      "kind" => "bitmap_sequence_at",
      "resource" => resource_name(resource),
      "animation_id" => resource_animation_id(resource, indices),
      "x" => x,
      "y" => y
    }
  end

  defp do_draw_row(%{"type" => "drawRotatedBitmap"} = node, opts) do
    {x, y} = point_xy(node, "origin")
    resource = Map.get(node, "resource") || Map.get(node, :resource)
    indices = bitmap_resource_indices(opts)
    bounds = Map.get(node, "bounds") || Map.get(node, :bounds) || %{}

    %{
      "kind" => "rotated_bitmap",
      "resource" => resource_name(resource),
      "bitmap_id" => resource_bitmap_id(resource, indices),
      "center_x" => x,
      "center_y" => y,
      "angle" => int_field(node, "rotation", int_field(node, "angle", 0)),
      "src_w" => int_field(bounds, "w", int_field(node, "src_w", 0)),
      "src_h" => int_field(bounds, "h", int_field(node, "src_h", 0))
    }
  end

  defp do_draw_row(%{"type" => "rect"} = node, _opts) do
    {x, y, w, h} = rect_fields(node, "bounds")

    %{
      "kind" => "rect",
      "x" => x,
      "y" => y,
      "w" => w,
      "h" => h,
      "fill" => int_field(node, "color", 0)
    }
  end

  defp do_draw_row(%{"type" => "roundRect"} = node, _opts) do
    {x, y, w, h} = rect_bounds(node, "bounds")

    %{
      "kind" => "round_rect",
      "x" => x,
      "y" => y,
      "w" => w,
      "h" => h,
      "radius" => int_field(node, "radius", 0),
      "fill" => int_field(node, "fill", int_field(node, "color", 0))
    }
  end

  defp do_draw_row(%{"type" => "line"} = node, _opts) do
    {x1, y1, x2, y2} = line_endpoints(node)

    %{
      "kind" => "line",
      "x1" => x1,
      "y1" => y1,
      "x2" => x2,
      "y2" => y2,
      "color" => int_field(node, "color", 0)
    }
  end

  defp do_draw_row(%{"type" => "circle"} = node, _opts) do
    {cx, cy} = point_fields(node, "center")
    {cx, cy} = point_fields(node, "position", {cx, cy})

    %{
      "kind" => "circle",
      "cx" => int_field(node, "cx", cx),
      "cy" => int_field(node, "cy", cy),
      "r" => int_field(node, "radius", int_field(node, "r", 0)),
      "color" => int_field(node, "color", 0)
    }
  end

  defp do_draw_row(%{"type" => "fillCircle"} = node, _opts) do
    {cx, cy} = point_fields(node, "center")
    {cx, cy} = point_fields(node, "position", {cx, cy})

    %{
      "kind" => "fill_circle",
      "cx" => int_field(node, "cx", cx),
      "cy" => int_field(node, "cy", cy),
      "r" => int_field(node, "radius", int_field(node, "r", 0)),
      "color" => int_field(node, "color", 0)
    }
  end

  defp do_draw_row(%{"type" => "pixel"} = node, _opts) do
    {x, y} = point_xy(node, "position")

    %{
      "kind" => "pixel",
      "x" => x,
      "y" => y,
      "color" => int_field(node, "color", 0)
    }
  end

  defp do_draw_row(%{"type" => "drawVectorAt"} = node, opts) do
    {x, y} = point_xy(node, "origin")
    resource = Map.get(node, "resource") || Map.get(node, :resource)
    indices = vector_resource_indices(opts)

    %{
      "kind" => "vector_at",
      "resource" => resource_name(resource),
      "vector_id" => vector_id(node, resource, indices),
      "x" => x,
      "y" => y
    }
  end

  defp do_draw_row(%{"type" => "drawVectorSequenceAt"} = node, opts) do
    {x, y} = point_xy(node, "origin")
    resource = Map.get(node, "resource") || Map.get(node, :resource)
    indices = vector_resource_indices(opts)

    %{
      "kind" => "vector_sequence_at",
      "resource" => resource_name(resource),
      "vector_id" => vector_id(node, resource, indices),
      "x" => x,
      "y" => y
    }
  end

  defp do_draw_row(%{"type" => "text"} = node, _opts) do
    {x, y, w, h} = rect_bounds(node, "bounds")

    %{
      "kind" => "text",
      "x" => x,
      "y" => y,
      "w" => w,
      "h" => h,
      "font_id" => int_field(node, "font_id", 0),
      "text" => text_content(node),
      "text_align" => text_align(node),
      "text_overflow" => text_overflow(node)
    }
  end

  defp do_draw_row(%{"type" => "textInt"} = node, _opts) do
    {x, y} = point_xy(node, "position")

    %{
      "kind" => "text_int",
      "x" => x,
      "y" => y,
      "font_id" => int_field(node, "font_id", 0),
      "text" => text_content(node)
    }
  end

  defp do_draw_row(%{"type" => "textLabel"} = node, _opts) do
    {x, y} = point_xy(node, "position")

    %{
      "kind" => "text_label",
      "x" => x,
      "y" => y,
      "font_id" => int_field(node, "font_id", 0),
      "text" => label_display_text(node)
    }
  end

  defp do_draw_row(%{"type" => "arc"} = node, _opts) do
    {x, y, w, h} = rect_fields(node, "bounds")

    %{
      "kind" => "arc",
      "x" => x,
      "y" => y,
      "w" => w,
      "h" => h,
      "start_angle" => int_field(node, "start_angle", 0),
      "end_angle" => int_field(node, "end_angle", 0)
    }
  end

  defp do_draw_row(%{"type" => "fillRadial"} = node, _opts) do
    {x, y, w, h} = rect_fields(node, "bounds")

    %{
      "kind" => "fill_radial",
      "x" => x,
      "y" => y,
      "w" => w,
      "h" => h,
      "start_angle" => int_field(node, "start_angle", 0),
      "end_angle" => int_field(node, "end_angle", 0)
    }
  end

  defp do_draw_row(%{"type" => type} = node, _opts)
       when type in ["pathFilled", "pathOutline", "pathOutlineOpen"] do
    case path_draw_row(type, node) do
      %{} = row -> row
      _ -> nil
    end
  end

  defp do_draw_row(_node, _opts), do: nil

  defp path_draw_row(type, node) when type in ["pathFilled", "pathOutline", "pathOutlineOpen"] do
    path = Map.get(node, "path") || Map.get(node, :path) || node

    case path_fields(path) do
      %{"points" => [_ | _]} = fields ->
        Map.put(fields, "kind", path_output_kind(type))

      _ ->
        nil
    end
  end

  defp path_output_kind("pathFilled"), do: "path_filled"
  defp path_output_kind("pathOutline"), do: "path_outline"
  defp path_output_kind("pathOutlineOpen"), do: "path_outline_open"

  defp path_fields(path) when is_map(path) do
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

  defp path_fields(_), do: %{"points" => [], "offset_x" => 0, "offset_y" => 0, "rotation" => 0}

  defp point_xy_map(%{"x" => x, "y" => y}) when is_integer(x) and is_integer(y), do: {x, y}
  defp point_xy_map(%{x: x, y: y}) when is_integer(x) and is_integer(y), do: {x, y}
  defp point_xy_map({x, y}) when is_integer(x) and is_integer(y), do: {x, y}
  defp point_xy_map([x, y]) when is_integer(x) and is_integer(y), do: {x, y}
  defp point_xy_map(_), do: {0, 0}

  defp normalize_path_points_list(points) when is_list(points) do
    points
    |> Enum.map(&normalize_path_point/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_path_points_list(_), do: []

  defp normalize_path_point([x, y]) when is_integer(x) and is_integer(y), do: [x, y]
  defp normalize_path_point({x, y}) when is_integer(x) and is_integer(y), do: [x, y]
  defp normalize_path_point(%{"x" => x, "y" => y}) when is_integer(x) and is_integer(y), do: [x, y]
  defp normalize_path_point(%{x: x, y: y}) when is_integer(x) and is_integer(y), do: [x, y]
  defp normalize_path_point(_), do: nil

  defp rect_fields(node, key) do
    bounds = Map.get(node, key) || Map.get(node, String.to_atom(key)) || %{}
    rect_bounds_from_value(bounds)
  end

  defp rect_bounds_from_value(%{"x" => x, "y" => y, "w" => w, "h" => h}),
    do: {rect_int(x), rect_int(y), rect_int(w), rect_int(h)}

  defp rect_bounds_from_value(%{x: x, y: y, w: w, h: h}),
    do: {rect_int(x), rect_int(y), rect_int(w), rect_int(h)}

  defp rect_bounds_from_value({x, y, w, h}) when is_integer(x),
    do: {rect_int(x), rect_int(y), rect_int(w), rect_int(h)}

  defp rect_bounds_from_value([x, y, w, h]) when is_integer(x),
    do: {rect_int(x), rect_int(y), rect_int(w), rect_int(h)}

  defp rect_bounds_from_value(bounds) when is_map(bounds) do
    {x, y} = point_fields(bounds, "origin", {0, 0})
    w = int_field(bounds, "w", int_field(bounds, "width", 0))
    h = int_field(bounds, "h", int_field(bounds, "height", 0))
    {int_field(bounds, "x", x), int_field(bounds, "y", y), w, h}
  end

  defp rect_bounds_from_value(_), do: {0, 0, 0, 0}

  defp rect_int(value) when is_integer(value), do: value
  defp rect_int(value) when is_float(value), do: trunc(value)
  defp rect_int(_), do: 0

  defp line_endpoints(node) when is_map(node) do
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

  defp rect_bounds(node, nested_key) do
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

  defp point_xy(node, nested_key, default \\ {0, 0}) do
    x = int_field(node, "x", nil)
    y = int_field(node, "y", nil)

    if is_integer(x) and is_integer(y) do
      {x, y}
    else
      point_fields(node, nested_key, default)
    end
  end

  defp point_fields(node, key, default \\ {0, 0}) do
    point = Map.get(node, key) || Map.get(node, String.to_atom(key)) || %{}
    {int_field(point, "x", elem(default, 0)), int_field(point, "y", elem(default, 1))}
  end

  defp text_content(node) when is_map(node) do
    value =
      Map.get(node, "text") || Map.get(node, :text) || Map.get(node, "label") ||
        Map.get(node, :label) || Map.get(node, "value") || Map.get(node, :value)

    to_string(value || "")
  end

  defp label_display_text(node) when is_map(node) do
    text_content(node)
    |> case do
      "WaitingForCompanion" -> "Waiting for companion app"
      text -> text
    end
  end

  defp text_align(node) do
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

  defp text_overflow(node) do
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

  defp vector_id(node, resource, indices) do
    case int_field(node, "vector_id", nil) do
      id when is_integer(id) and id > 0 ->
        id

      _ ->
        resource_vector_id(resource, indices)
    end
  end

  defp vector_resource_indices(opts) when is_list(opts) do
    case Keyword.get(opts, :vector_resource_indices) do
      %{} = indices -> indices
      _ -> %{}
    end
  end

  defp animation_resource_indices(opts) when is_list(opts) do
    case Keyword.get(opts, :animation_resource_indices) do
      %{} = indices -> indices
      _ -> %{}
    end
  end

  defp apply_vector_resource_index(row, indices) when is_map(row) and is_map(indices) do
    kind = Map.get(row, "kind") || Map.get(row, :kind)

    if kind in ["vector_at", "vector_sequence_at", :vector_at, :vector_sequence_at] do
      case int_field(row, "vector_id", 0) do
        id when is_integer(id) and id > 0 ->
          row

        _ ->
          resource = Map.get(row, "resource") || Map.get(row, :resource)
          id = resource_vector_id(resource, indices)
          if id > 0, do: Map.put(row, "vector_id", id), else: row
      end
    else
      row
    end
  end

  defp apply_vector_resource_index(row, _indices), do: row

  defp apply_animation_resource_index(row, indices) when is_map(row) and is_map(indices) do
    kind = Map.get(row, "kind") || Map.get(row, :kind)

    if kind in ["bitmap_sequence_at", :bitmap_sequence_at] do
      case int_field(row, "animation_id", 0) do
        id when is_integer(id) and id > 0 ->
          row

        _ ->
          resource = Map.get(row, "resource") || Map.get(row, :resource)
          id = resource_animation_id(resource, indices)

          if id > 0, do: Map.put(row, "animation_id", id), else: row
      end
    else
      row
    end
  end

  defp apply_animation_resource_index(row, _indices), do: row

  defp apply_bitmap_resource_index(row, indices) when is_map(row) and is_map(indices) do
    kind = Map.get(row, "kind") || Map.get(row, :kind)

    if kind in ["bitmap_in_rect", "rotated_bitmap", :bitmap_in_rect, :rotated_bitmap] do
      case int_field(row, "bitmap_id", 0) do
        id when is_integer(id) and id > 0 ->
          row

        _ ->
          resource = Map.get(row, "resource") || Map.get(row, :resource)
          id = resource_bitmap_id(resource, indices)
          if id > 0, do: Map.put(row, "bitmap_id", id), else: row
      end
    else
      row
    end
  end

  defp apply_bitmap_resource_index(row, _indices), do: row

  defp bitmap_resource_indices(opts) when is_list(opts) do
    case Keyword.get(opts, :bitmap_resource_indices) do
      %{} = indices -> indices
      _ -> %{}
    end
  end

  defp resource_name(resource) when is_binary(resource), do: resource
  defp resource_name(resource) when is_atom(resource), do: Atom.to_string(resource)
  defp resource_name(%{"ctor" => ctor}), do: to_string(ctor)
  defp resource_name(%{ctor: ctor}), do: to_string(ctor)
  defp resource_name(_), do: ""

  defp resource_bitmap_id(resource, indices), do: resource_index_id(resource, indices)

  defp resource_animation_id(resource, indices), do: resource_index_id(resource, indices)

  defp resource_index_id(resource, indices), do: resource_vector_id(resource, indices)

  defp sanitize_rect({x, y, w, h}, _node, opts) do
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

  defp screen_dimension(opts, key) when is_list(opts) do
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

  defp screen_key_fallback(:screen_w), do: "screenW"
  defp screen_key_fallback(:screen_h), do: "screenH"

  defp resource_vector_id(resource, indices) when is_map(indices) do
    case resource do
      id when is_integer(id) and id > 0 ->
        id

      resource ->
        name = resource_name(resource)

        case Map.get(indices, name) || Map.get(indices, String.to_atom(name)) do
          id when is_integer(id) and id > 0 ->
            id

          _ ->
            case Integer.parse(name) do
              {id, ""} when id > 0 -> id
              _ -> 0
            end
        end
    end
  end

  defp int_field(node, key, default) when is_map(node) do
    case Map.get(node, key) || Map.get(node, String.to_atom(key)) do
      value when is_integer(value) -> value
      value when is_float(value) -> trunc(value)
      _ -> default
    end
  end
end
