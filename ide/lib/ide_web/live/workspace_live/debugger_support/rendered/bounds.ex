defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Rendered.Bounds do
  @moduledoc false

  alias Ide.Resources.PdcDecoder
  alias Ide.Resources.ResourceStore
  alias Ide.Projects.Project
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Rendered.Expr
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Util

  @type rendered_node :: Types.rendered_node()
  @type view_tree :: Types.view_tree()
  @type bounds_map :: Types.bounds_map()
  @type path_payload :: Types.path_payload()
  @type path_point :: {integer(), integer()} | rendered_node()

  @spec rendered_node_bounds(
          rendered_node() | view_tree(),
          String.t(),
          integer(),
          integer(),
          Project.t() | nil
        ) :: bounds_map() | nil
  def rendered_node_bounds(tree, path, screen_w, screen_h, project \\ nil)

  def rendered_node_bounds(tree, path, screen_w, screen_h, project)
      when is_map(tree) and is_binary(path) do
    tree
    |> rendered_node_at_path(path)
    |> rendered_bounds_for_node(screen_w, screen_h, project)
  end

  def rendered_node_bounds(_tree, _path, _screen_w, _screen_h, _project), do: nil

  @spec rendered_node_at_path(view_tree(), String.t()) :: rendered_node() | nil
  defp rendered_node_at_path(tree, path) when is_map(tree) and is_binary(path) do
    indexes =
      path
      |> String.split(".", trim: true)
      |> Enum.map(&Integer.parse/1)

    case indexes do
      [{0, ""} | rest] -> rendered_node_at_indexes(tree, rest)
      [] -> tree
      _ -> nil
    end
  end

  @spec rendered_node_at_indexes(rendered_node(), [{integer(), String.t()}]) ::
          rendered_node() | nil
  defp rendered_node_at_indexes(node, []) when is_map(node), do: node

  defp rendered_node_at_indexes(node, [{index, ""} | rest]) when is_map(node) and index >= 0 do
    children = Map.get(node, "children") || Map.get(node, :children) || []

    children
    |> Enum.filter(&is_map/1)
    |> Enum.at(index)
    |> rendered_node_at_indexes(rest)
  end

  defp rendered_node_at_indexes(_node, _indexes), do: nil

  @spec rendered_bounds_for_node(rendered_node(), integer(), integer(), Project.t() | nil) ::
          bounds_map() | nil
  defp rendered_bounds_for_node(node, screen_w, screen_h, project) when is_map(node) do
    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "")

    case type do
      "clear" ->
        w = if is_integer(screen_w), do: screen_w, else: 0
        h = if is_integer(screen_h), do: screen_h, else: 0
        %{x: 0, y: 0, w: max(w, 1), h: max(h, 1)}

      type
      when type in [
             "roundRect",
             "rect",
             "fillRect",
             "text",
             "bitmapInRect",
             "drawBitmapInRect",
             "arc",
             "fillRadial"
           ] ->
        rect_bounds(node)

      type when type in ["pathFilled", "pathOutline", "pathOutlineOpen"] ->
        path_bounds(node)

      "line" ->
        line_bounds(node)

      "pixel" ->
        with x when is_integer(x) <- node_point_integer(node, :x),
             y when is_integer(y) <- node_point_integer(node, :y) do
          %{x: x, y: y, w: 1, h: 1}
        else
          _ -> nil
        end

      type when type in ["circle", "fillCircle"] ->
        circle_bounds(node)

      "textInt" ->
        text_point_bounds(node, 48, 14)

      "textLabel" ->
        text_point_bounds(node, 56, 12)

      type when type in ["rotatedBitmap", "drawRotatedBitmap"] ->
        rotated_bitmap_bounds(node)

      type when type in ["drawVectorAt", "vectorAt"] ->
        vector_at_bounds(node, project, :image)

      type when type in ["drawVectorSequenceAt", "vectorSequenceAt"] ->
        vector_at_bounds(node, project, :sequence)

      type when type in ["drawBitmapSequenceAt", "bitmapSequenceAt"] ->
        animation_at_bounds(node, project)

      _ ->
        aggregate_child_bounds(node, screen_w, screen_h, project)
    end
  end

  defp rendered_bounds_for_node(_node, _screen_w, _screen_h, _project), do: nil

  @spec animation_at_bounds(rendered_node(), Project.t() | nil) :: bounds_map() | nil
  defp animation_at_bounds(node, %Project{} = project) when is_map(node) do
    with animation_id when is_integer(animation_id) and animation_id >= 1 <-
           Util.map_integer(node, :animation_id),
         x when is_integer(x) <- node_point_integer(node, :x),
         y when is_integer(y) <- node_point_integer(node, :y),
         {:ok, path} <- ResourceStore.animation_file_path_by_id(project, animation_id),
         {:ok, probe} <- Ide.Resources.ApngProbe.probe(path) do
      %{x: x, y: y, w: max(probe.width, 1), h: max(probe.height, 1)}
    else
      _ -> nil
    end
  end

  defp animation_at_bounds(_node, _project), do: nil

  @spec vector_at_bounds(rendered_node(), Project.t() | nil, :image | :sequence) ::
          bounds_map() | nil
  defp vector_at_bounds(node, project, kind) when is_map(node) and kind in [:image, :sequence] do
    with x when is_integer(x) <- node_point_integer(node, :x),
         y when is_integer(y) <- node_point_integer(node, :y),
         {:ok, {w, h}} <- vector_canvas_size(node, project, kind) do
      %{x: x, y: y, w: max(w, 1), h: max(h, 1)}
    else
      _ -> nil
    end
  end

  @spec vector_canvas_size(rendered_node(), Project.t() | nil, :image | :sequence) ::
          {:ok, {integer(), integer()}} | :error
  defp vector_canvas_size(node, %Project{} = project, kind) when is_map(node) do
    with vector_id when is_integer(vector_id) and vector_id >= 1 <-
           Util.map_integer(node, :vector_id),
         {:ok, path} <- ResourceStore.vector_file_path_by_id(project, vector_id),
         {:ok, bytes} <- File.read(path),
         {:ok, {w, h}} <- PdcDecoder.decode_canvas_size(bytes, kind) do
      {:ok, {w, h}}
    else
      _ -> :error
    end
  end

  defp vector_canvas_size(_node, _project, _kind), do: :error

  @spec rect_bounds(rendered_node()) :: bounds_map() | nil
  defp rect_bounds(node) when is_map(node) do
    with x when is_integer(x) <- node_rect_integer(node, :x),
         y when is_integer(y) <- node_rect_integer(node, :y),
         w when is_integer(w) <- node_rect_integer(node, :w),
         h when is_integer(h) <- node_rect_integer(node, :h) do
      %{x: x, y: y, w: max(w, 1), h: max(h, 1)}
    else
      _ -> nil
    end
  end

  @spec node_bounds_map(rendered_node()) :: bounds_map()
  defp node_bounds_map(node) when is_map(node) do
    Util.map_map(node, :bounds)
  end

  @spec node_rect_integer(rendered_node(), atom()) :: integer() | nil
  defp node_rect_integer(node, key) when is_map(node) and is_atom(key) do
    bounds = node_bounds_map(node)

    Util.map_integer(node, key) ||
      Util.map_integer(bounds, key)
  end

  @spec node_point_integer(rendered_node(), atom()) :: integer() | nil
  defp node_point_integer(node, key) when is_map(node) and key in [:x, :y] do
    origin = Util.map_map(node, :origin)

    Util.map_integer(node, key) ||
      Util.map_integer(origin, key) ||
      node_rect_integer(node, key)
  end

  @spec line_bounds(rendered_node()) :: bounds_map() | nil
  defp line_bounds(node) when is_map(node) do
    with x1 when is_integer(x1) <- Util.map_integer(node, :x1),
         y1 when is_integer(y1) <- Util.map_integer(node, :y1),
         x2 when is_integer(x2) <- Util.map_integer(node, :x2),
         y2 when is_integer(y2) <- Util.map_integer(node, :y2) do
      x = min(x1, x2)
      y = min(y1, y2)
      %{x: x, y: y, w: max(abs(x2 - x1), 1), h: max(abs(y2 - y1), 1)}
    else
      _ -> nil
    end
  end

  @spec circle_bounds(rendered_node()) :: bounds_map() | nil
  defp circle_bounds(node) when is_map(node) do
    with cx when is_integer(cx) <- Util.map_integer(node, :cx) || node_point_integer(node, :x),
         cy when is_integer(cy) <- Util.map_integer(node, :cy) || node_point_integer(node, :y),
         r when is_integer(r) <- Util.map_integer(node, :r) do
      radius = max(r, 1)
      %{x: cx - radius, y: cy - radius, w: radius * 2, h: radius * 2}
    else
      _ -> nil
    end
  end

  @spec text_point_bounds(rendered_node(), integer(), integer()) :: bounds_map() | nil
  defp text_point_bounds(node, default_w, default_h) when is_map(node) do
    case rect_bounds(node) do
      %{w: w, h: h} = box when w > 0 and h > 0 ->
        box

      _ ->
        with x when is_integer(x) <- node_point_integer(node, :x),
             y when is_integer(y) <- node_point_integer(node, :y) do
          %{x: x, y: y - default_h, w: default_w, h: default_h}
        else
          _ -> nil
        end
    end
  end

  @spec rotated_bitmap_bounds(rendered_node()) :: bounds_map() | nil
  defp rotated_bitmap_bounds(node) when is_map(node) do
    with center_x when is_integer(center_x) <-
           Util.map_integer(node, :center_x) || node_point_integer(node, :x),
         center_y when is_integer(center_y) <-
           Util.map_integer(node, :center_y) || node_point_integer(node, :y),
         src_w when is_integer(src_w) <-
           Util.map_integer(node, :src_w) || node_rect_integer(node, :w),
         src_h when is_integer(src_h) <-
           Util.map_integer(node, :src_h) || node_rect_integer(node, :h) do
      angle = Util.map_integer(node, :angle) || Util.map_integer(node, :rotation) || 0

      rotated_points_bounds(
        [
          {-src_w / 2.0, -src_h / 2.0},
          {src_w / 2.0, -src_h / 2.0},
          {src_w / 2.0, src_h / 2.0},
          {-src_w / 2.0, src_h / 2.0}
        ],
        center_x,
        center_y,
        angle
      )
    else
      _ -> nil
    end
  end

  @spec path_bounds(rendered_node()) :: bounds_map() | nil
  defp path_bounds(node) when is_map(node) do
    payload = path_payload_from_children(node)
    points = Map.get(node, "points") || Map.get(node, :points) || Map.get(payload, :points, [])
    offset_x = Util.map_integer(node, :offset_x) || Map.get(payload, :offset_x, 0)
    offset_y = Util.map_integer(node, :offset_y) || Map.get(payload, :offset_y, 0)
    rotation = Util.map_integer(node, :rotation) || Map.get(payload, :rotation, 0)

    points
    |> normalize_path_points()
    |> case do
      [] -> nil
      normalized -> rotated_points_bounds(normalized, offset_x, offset_y, rotation)
    end
  end

  @spec rotated_points_bounds([{number(), number()}], number(), number(), integer()) ::
          bounds_map() | nil
  defp rotated_points_bounds(points, offset_x, offset_y, rotation)
       when is_list(points) and is_number(offset_x) and is_number(offset_y) and
              is_integer(rotation) do
    rotation_rad = rotation * 2.0 * :math.pi() / 65_536.0
    cos_r = :math.cos(rotation_rad)
    sin_r = :math.sin(rotation_rad)

    transformed =
      Enum.map(points, fn {x, y} ->
        xr = x * cos_r - y * sin_r
        yr = x * sin_r + y * cos_r
        {xr + offset_x, yr + offset_y}
      end)

    case transformed do
      [] ->
        nil

      _ ->
        xs = Enum.map(transformed, fn {x, _y} -> x end)
        ys = Enum.map(transformed, fn {_x, y} -> y end)
        min_x = Enum.min(xs)
        min_y = Enum.min(ys)
        max_x = Enum.max(xs)
        max_y = Enum.max(ys)

        %{
          x: rendered_bounds_number(Float.floor(min_x, 2)),
          y: rendered_bounds_number(Float.floor(min_y, 2)),
          w: rendered_bounds_number(max(Float.ceil(max_x - min_x, 2), 1)),
          h: rendered_bounds_number(max(Float.ceil(max_y - min_y, 2), 1))
        }
    end
  end

  @spec rendered_bounds_number(number()) :: number()
  defp rendered_bounds_number(value) when is_float(value) do
    rounded = round(value)
    if Float.round(value, 6) == rounded * 1.0, do: rounded, else: value
  end

  defp rendered_bounds_number(value), do: value

  @spec path_payload_from_children(rendered_node()) :: path_payload()
  defp path_payload_from_children(node) when is_map(node) do
    case Map.get(node, "children") || Map.get(node, :children) || [] do
      [%{"points" => points} = payload | _] ->
        %{
          points: points,
          offset_x: Util.map_integer(payload, :offset_x) || 0,
          offset_y: Util.map_integer(payload, :offset_y) || 0,
          rotation: Util.map_integer(payload, :rotation) || 0
        }

      [%{points: points} = payload | _] ->
        %{
          points: points,
          offset_x: Util.map_integer(payload, :offset_x) || 0,
          offset_y: Util.map_integer(payload, :offset_y) || 0,
          rotation: Util.map_integer(payload, :rotation) || 0
        }

      [payload | _] ->
        path_payload_from_node(payload)

      _ ->
        %{}
    end
  end

  @spec path_payload_from_node(rendered_node()) :: path_payload()
  defp path_payload_from_node(payload) do
    with {:ok, [points_node, offset_node, rotation_node]} <- Expr.payload_args(payload, 3),
         points when points != [] <- normalize_path_points_from_node(points_node),
         {offset_x, offset_y} <- normalize_path_point(offset_node),
         rotation when is_integer(rotation) <- Expr.expr_scalar(rotation_node) do
      %{points: points, offset_x: offset_x, offset_y: offset_y, rotation: rotation}
    else
      _ -> %{}
    end
  end

  @spec normalize_path_points_from_node(rendered_node()) :: [{integer(), integer()}]
  defp normalize_path_points_from_node(%{"type" => "List", "children" => points})
       when is_list(points),
       do: normalize_path_points(points)

  defp normalize_path_points_from_node(points), do: normalize_path_points(points)

  @spec normalize_path_points(list()) :: [{integer(), integer()}]
  defp normalize_path_points(points) when is_list(points) do
    points
    |> Enum.map(&normalize_path_point/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_path_points(_points), do: []

  @spec normalize_path_point(path_point()) :: {integer(), integer()} | nil
  defp normalize_path_point([x, y]) when is_integer(x) and is_integer(y), do: {x, y}

  defp normalize_path_point(%{"x" => x, "y" => y}) when is_integer(x) and is_integer(y),
    do: {x, y}

  defp normalize_path_point(%{x: x, y: y}) when is_integer(x) and is_integer(y), do: {x, y}

  defp normalize_path_point(%{"type" => "tuple2", "children" => [x_node, y_node]}) do
    x = Expr.expr_scalar(x_node)
    y = Expr.expr_scalar(y_node)
    if is_integer(x) and is_integer(y), do: {x, y}, else: nil
  end

  defp normalize_path_point(%{type: "tuple2", children: [x_node, y_node]}) do
    x = Expr.expr_scalar(x_node)
    y = Expr.expr_scalar(y_node)
    if is_integer(x) and is_integer(y), do: {x, y}, else: nil
  end

  defp normalize_path_point(_point), do: nil

  @spec aggregate_child_bounds(rendered_node(), integer(), integer(), Project.t() | nil) ::
          bounds_map() | nil
  defp aggregate_child_bounds(node, screen_w, screen_h, project) when is_map(node) do
    node
    |> Map.get("children", Map.get(node, :children, []))
    |> Enum.filter(&is_map/1)
    |> Enum.map(&rendered_bounds_for_node(&1, screen_w, screen_h, project))
    |> Enum.reject(&is_nil/1)
    |> union_bounds()
  end

  @spec union_bounds([bounds_map()]) :: bounds_map() | nil
  defp union_bounds([]), do: nil

  defp union_bounds([first | rest]) do
    Enum.reduce(rest, first, fn box, acc ->
      min_x = min(acc.x, box.x)
      min_y = min(acc.y, box.y)
      max_x = max(acc.x + acc.w, box.x + box.w)
      max_y = max(acc.y + acc.h, box.y + box.h)
      %{x: min_x, y: min_y, w: max(max_x - min_x, 1), h: max(max_y - min_y, 1)}
    end)
  end
end
