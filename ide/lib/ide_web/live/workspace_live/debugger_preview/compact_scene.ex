defmodule IdeWeb.WorkspaceLive.DebuggerPreview.CompactScene do
  @moduledoc false

  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.RuntimePreview
  alias IdeWeb.WorkspaceLive.DebuggerPreview.{RuntimeAccess, SvgOpNormalize, Wire}
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: PreviewTypes

  @type runtime_input :: PreviewTypes.runtime_input()
  @type wire_value :: PreviewTypes.wire_value()
  @type svg_op :: PreviewTypes.svg_op()
  @type compact_scene :: PreviewTypes.compact_scene()
  @type bounds_map :: PreviewTypes.bounds_map()
  @type unresolved_row :: PreviewTypes.unresolved_row()
  @type compact_scene_op :: PreviewTypes.compact_scene_op()
  @type hash_input :: PreviewTypes.hash_input()
  @type preview_target :: :watch | :companion | :phone

  @path_drawable_kinds ~w(path_filled path_outline path_outline_open)

  @spec compact_scene(runtime_input()) :: compact_scene()
  def compact_scene(runtime) when is_map(runtime), do: compact_scene(runtime, :watch)
  def compact_scene(_runtime), do: build_compact_scene([])

  @spec compact_scene(runtime_input(), :watch | :companion | :phone) :: compact_scene()
  def compact_scene(runtime, target)
      when is_map(runtime) and target in [:watch, :companion, :phone] do
    model = Map.get(runtime, :model) || Map.get(runtime, "model") || %{}
    rows = RuntimePreview.effective_runtime_view_output_rows(runtime, model, target)

    case Map.get(model, "compact_scene") || Map.get(model, :compact_scene) ||
           Map.get(model, "runtime_compact_scene") || Map.get(model, :runtime_compact_scene) do
      scene when is_map(scene) ->
        normalized = normalize_compact_scene(scene)

        if compact_scene_missing_path_drawables?(normalized, rows) or
             compact_scene_missing_bitmap_drawables?(normalized, rows) do
          build_compact_scene_from_view_output_rows(runtime, model, rows)
        else
          normalized
        end

      _ ->
        build_compact_scene_from_view_output_rows(runtime, model, rows)
    end
  end

  def compact_scene(_runtime, _target), do: build_compact_scene([])

  @spec compact_scene_diff(compact_scene() | runtime_input(), compact_scene() | runtime_input()) ::
          PreviewTypes.compact_scene_diff()
  def compact_scene_diff(previous, current) do
    previous_scene = normalize_compact_scene_map(previous)
    current_scene = normalize_compact_scene_map(current)

    previous_ops = Map.get(previous_scene, :ops, [])
    current_ops = Map.get(current_scene, :ops, [])
    max_count = max(length(previous_ops), length(current_ops))

    dirty_bounds =
      0..max(max_count - 1, 0)
      |> Enum.flat_map(fn index ->
        previous_op = Enum.at(previous_ops, index)
        current_op = Enum.at(current_ops, index)

        cond do
          previous_op == nil and current_op == nil ->
            []

          op_hash(previous_op) == op_hash(current_op) ->
            []

          true ->
            [op_bounds(previous_op), op_bounds(current_op)]
            |> Enum.filter(&is_map/1)
        end
      end)
      |> merge_dirty_bounds()

    %{
      changed?: Map.get(previous_scene, :hash) != Map.get(current_scene, :hash),
      dirty_bounds: dirty_bounds,
      previous_hash: Map.get(previous_scene, :hash),
      current_hash: Map.get(current_scene, :hash)
    }
  end

  @spec unresolved_summary([unresolved_row()]) :: String.t()
  def unresolved_summary(rows) when is_list(rows) and rows != [] do
    sample =
      rows
      |> Enum.take(3)
      |> Enum.map(fn row ->
        "#{display_node_type(row.node_type)}(#{row.provided_int_count}/#{row.required_int_count})"
      end)
      |> Enum.join(", ")

    "Unresolved primitives (#{length(rows)}): #{sample}"
  end

  def unresolved_summary(_rows), do: ""

  @spec display_node_type(wire_value()) :: String.t()
  defp display_node_type(value) when is_binary(value), do: value
  defp display_node_type(_), do: "node"

  @spec build_compact_scene_from_view_output_rows(
          runtime_input(),
          PreviewTypes.wire_map(),
          [PreviewTypes.view_output_row()]
        ) :: compact_scene()
  defp build_compact_scene_from_view_output_rows(runtime, model, rows)
       when is_map(runtime) and is_map(model) and is_list(rows) do
    indices = RuntimeArtifacts.vector_resource_indices(RuntimeAccess.runtime_model(runtime))

    bitmap_indices =
      RuntimeArtifacts.bitmap_resource_indices(RuntimeAccess.runtime_model(runtime))

    ops =
      rows
      |> Elmx.Runtime.ViewOutput.apply_resource_indices(
        vector_resource_indices: indices,
        bitmap_resource_indices: bitmap_indices,
        animation_resource_indices:
          RuntimeArtifacts.animation_resource_indices(RuntimeAccess.runtime_model(runtime))
      )
      |> Enum.map(&SvgOpNormalize.normalize/1)
      |> Enum.reject(&is_nil/1)

    build_compact_scene(ops)
  end

  @spec compact_scene_missing_path_drawables?(compact_scene(), [PreviewTypes.view_output_row()]) ::
          boolean()
  defp compact_scene_missing_path_drawables?(scene, rows) when is_map(scene) and is_list(rows) do
    rows_need_paths? =
      Enum.any?(rows, fn row ->
        kind = view_output_row_kind(row)
        kind in ["path_filled", "path_outline", "path_outline_open"]
      end)

    rows_need_paths? and not compact_scene_has_path_drawables?(scene)
  end

  defp compact_scene_missing_path_drawables?(_scene, _rows), do: false

  @spec compact_scene_missing_bitmap_drawables?(compact_scene(), [PreviewTypes.view_output_row()]) ::
          boolean()
  defp compact_scene_missing_bitmap_drawables?(scene, rows)
       when is_map(scene) and is_list(rows) do
    rows_need_bitmaps? =
      Enum.any?(rows, fn row ->
        kind = view_output_row_kind(row)

        kind in ["bitmap_in_rect", "rotated_bitmap", "bitmap_sequence_at"] and
          view_output_row_has_resolved_resource_id?(row, kind)
      end)

    rows_need_bitmaps? and not compact_scene_has_bitmap_drawables?(scene)
  end

  defp compact_scene_missing_bitmap_drawables?(_scene, _rows), do: false

  defp view_output_row_has_resolved_resource_id?(row, "bitmap_in_rect"),
    do: view_output_row_int(row, "bitmap_id", 0) > 0

  defp view_output_row_has_resolved_resource_id?(row, "rotated_bitmap"),
    do: view_output_row_int(row, "bitmap_id", 0) > 0

  defp view_output_row_has_resolved_resource_id?(row, "bitmap_sequence_at"),
    do: view_output_row_int(row, "bitmap_animation_id", 0) > 0

  defp view_output_row_has_resolved_resource_id?(_row, _kind), do: false

  defp view_output_row_int(row, key, default) when is_map(row) do
    case Map.get(row, key) || Map.get(row, String.to_atom(key)) do
      n when is_integer(n) -> n
      n when is_float(n) -> trunc(n)
      _ -> default
    end
  end

  @spec compact_scene_has_bitmap_drawables?(compact_scene()) :: boolean()
  defp compact_scene_has_bitmap_drawables?(scene) when is_map(scene) do
    scene
    |> Map.get(:ops, Map.get(scene, "ops", []))
    |> List.wrap()
    |> Enum.any?(fn entry ->
      op = Map.get(entry, :op) || Map.get(entry, "op") || %{}
      kind = to_string(Map.get(op, :kind) || Map.get(op, "kind") || "")

      kind in ["bitmap_in_rect", "rotated_bitmap", "bitmap_sequence_at"] and
        compact_op_has_resolved_resource_id?(op, kind)
    end)
  end

  defp compact_op_has_resolved_resource_id?(op, "bitmap_in_rect"),
    do: compact_op_int(op, "bitmap_id", 0) > 0

  defp compact_op_has_resolved_resource_id?(op, "rotated_bitmap"),
    do: compact_op_int(op, "bitmap_id", 0) > 0

  defp compact_op_has_resolved_resource_id?(op, "bitmap_sequence_at"),
    do: compact_op_int(op, "bitmap_animation_id", 0) > 0

  defp compact_op_has_resolved_resource_id?(_op, _kind), do: false

  defp compact_op_int(op, key, default) when is_map(op) do
    case Map.get(op, key) || Map.get(op, String.to_atom(key)) do
      n when is_integer(n) -> n
      n when is_float(n) -> trunc(n)
      _ -> default
    end
  end

  @spec compact_scene_has_path_drawables?(compact_scene()) :: boolean()
  defp compact_scene_has_path_drawables?(scene) when is_map(scene) do
    scene
    |> Map.get(:ops, Map.get(scene, "ops", []))
    |> List.wrap()
    |> Enum.any?(fn entry ->
      op = Map.get(entry, :op) || Map.get(entry, "op") || %{}
      kind = Map.get(op, :kind) || Map.get(op, "kind")
      to_string(kind) in @path_drawable_kinds
    end)
  end

  @spec view_output_row_kind(PreviewTypes.view_output_row()) :: String.t()
  defp view_output_row_kind(row) when is_map(row) do
    to_string(Map.get(row, "kind") || Map.get(row, :kind) || "")
  end

  @spec normalize_compact_scene(PreviewTypes.compact_scene() | PreviewTypes.wire_map()) ::
          compact_scene()
  defp normalize_compact_scene(scene) when is_map(scene) do
    ops =
      scene
      |> Map.get(:ops, Map.get(scene, "ops", []))
      |> List.wrap()
      |> Enum.map(fn
        %{op: op} = row when is_map(op) ->
          %{op: op, bounds: Map.get(row, :bounds), hash: Map.get(row, :hash) || stable_hash(op)}

        %{"op" => op} = row when is_map(op) ->
          op = atomize_known_op(op)
          %{op: op, bounds: Map.get(row, "bounds"), hash: Map.get(row, "hash") || stable_hash(op)}

        op when is_map(op) ->
          op = atomize_known_op(op)
          %{op: op, bounds: compact_op_bounds(op), hash: stable_hash(op)}

        _ ->
          nil
      end)
      |> Enum.reject(&is_nil/1)

    %{
      version: Map.get(scene, :version, Map.get(scene, "version", 1)),
      ops: ops,
      hash: stable_hash(Enum.map(ops, & &1.hash))
    }
  end

  @spec normalize_compact_scene_map(compact_scene() | runtime_input()) :: compact_scene()
  defp normalize_compact_scene_map(%{version: _, ops: _} = scene),
    do: normalize_compact_scene(scene)

  defp normalize_compact_scene_map(%{"version" => _, "ops" => _} = scene),
    do: normalize_compact_scene(scene)

  defp normalize_compact_scene_map(%{ops: _} = scene), do: normalize_compact_scene(scene)
  defp normalize_compact_scene_map(%{"ops" => _} = scene), do: normalize_compact_scene(scene)
  defp normalize_compact_scene_map(runtime) when is_map(runtime), do: compact_scene(runtime)
  defp normalize_compact_scene_map(_), do: build_compact_scene([])

  @spec build_compact_scene([svg_op()]) :: compact_scene()
  defp build_compact_scene(ops) when is_list(ops) do
    rows =
      Enum.map(ops, fn op ->
        %{op: op, bounds: compact_op_bounds(op), hash: stable_hash(op)}
      end)

    %{version: 1, ops: rows, hash: stable_hash(Enum.map(rows, & &1.hash))}
  end

  @spec atomize_known_op(PreviewTypes.wire_map()) :: svg_op()
  defp atomize_known_op(op) when is_map(op) do
    Enum.reduce(op, %{}, fn
      {"kind", value}, acc -> Map.put(acc, :kind, normalize_kind_atom(value))
      {key, value}, acc when is_binary(key) -> Map.put(acc, compact_key_atom(key) || key, value)
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  @spec normalize_kind_atom(String.t() | atom()) :: atom()
  defp normalize_kind_atom(value) when is_atom(value), do: value

  defp normalize_kind_atom(value) when is_binary(value) do
    value
    |> String.replace("-", "_")
    |> compact_kind_atom()
    |> case do
      nil -> value
      atom -> atom
    end
  end

  defp normalize_kind_atom(value), do: value

  @spec compact_key_atom(String.t()) :: atom() | nil
  defp compact_key_atom(key) do
    case key do
      "x" -> :x
      "y" -> :y
      "w" -> :w
      "h" -> :h
      "x1" -> :x1
      "y1" -> :y1
      "x2" -> :x2
      "y2" -> :y2
      "cx" -> :cx
      "cy" -> :cy
      "r" -> :r
      "fill" -> :fill
      "color" -> :color
      "radius" -> :radius
      "text" -> :text
      "points" -> :points
      "offset_x" -> :offset_x
      "offset_y" -> :offset_y
      "rotation" -> :rotation
      "start_angle" -> :start_angle
      "end_angle" -> :end_angle
      "bitmap_id" -> :bitmap_id
      "src_w" -> :src_w
      "src_h" -> :src_h
      "angle" -> :angle
      "center_x" -> :center_x
      "center_y" -> :center_y
      "value" -> :value
      "text_align" -> :text_align
      "text_overflow" -> :text_overflow
      "font_size" -> :font_size
      "source" -> :source
      _ -> nil
    end
  end

  @spec compact_kind_atom(String.t()) :: atom() | nil
  defp compact_kind_atom(kind) do
    case kind do
      "push_context" -> :push_context
      "pop_context" -> :pop_context
      "stroke_width" -> :stroke_width
      "antialiased" -> :antialiased
      "stroke_color" -> :stroke_color
      "fill_color" -> :fill_color
      "text_color" -> :text_color
      "compositing_mode" -> :compositing_mode
      "clear" -> :clear
      "round_rect" -> :round_rect
      "rect" -> :rect
      "fill_rect" -> :fill_rect
      "line" -> :line
      "arc" -> :arc
      "fill_radial" -> :fill_radial
      "path_filled" -> :path_filled
      "path_outline" -> :path_outline
      "path_outline_open" -> :path_outline_open
      "circle" -> :circle
      "fill_circle" -> :fill_circle
      "pixel" -> :pixel
      "bitmap_in_rect" -> :bitmap_in_rect
      "rotated_bitmap" -> :rotated_bitmap
      "vector_at" -> :vector_at
      "vector_sequence_at" -> :vector_sequence_at
      "bitmap_sequence_at" -> :bitmap_sequence_at
      "text_int" -> :text_int
      "text_label" -> :text_label
      "text" -> :text
      "unresolved" -> :unresolved
      _ -> nil
    end
  end

  @spec compact_op_bounds(svg_op()) :: bounds_map() | nil
  defp compact_op_bounds(%{kind: kind})
       when kind in [
              :push_context,
              :pop_context,
              :stroke_width,
              :antialiased,
              :stroke_color,
              :fill_color,
              :text_color,
              :compositing_mode
            ],
       do: nil

  defp compact_op_bounds(%{kind: :clear}), do: nil

  defp compact_op_bounds(%{kind: kind, x: x, y: y, w: w, h: h})
       when kind in [
              :rect,
              :fill_rect,
              :round_rect,
              :arc,
              :fill_radial,
              :bitmap_in_rect,
              :bitmap_sequence_at,
              :text_label
            ] do
    bounds_map(x, y, w, h)
  end

  defp compact_op_bounds(%{kind: :bitmap_sequence_at, x: x, y: y, width: w, height: h}) do
    bounds_map(x, y, w, h)
  end

  defp compact_op_bounds(%{kind: kind, x: x, y: y})
       when kind in [:text_int, :text_label, :text] do
    bounds_map(x, y, 144, 24)
  end

  defp compact_op_bounds(%{kind: kind, cx: cx, cy: cy, r: r})
       when kind in [:circle, :fill_circle] do
    bounds_map(cx - r, cy - r, r * 2, r * 2)
  end

  defp compact_op_bounds(%{kind: :pixel, x: x, y: y}), do: bounds_map(x, y, 1, 1)

  defp compact_op_bounds(%{kind: :line, x1: x1, y1: y1, x2: x2, y2: y2}) do
    x = min(x1, x2)
    y = min(y1, y2)
    bounds_map(x, y, abs(x2 - x1) + 1, abs(y2 - y1) + 1)
  end

  defp compact_op_bounds(%{points: points, offset_x: ox, offset_y: oy}) when is_list(points) do
    coords =
      points
      |> Enum.filter(&is_map/1)
      |> Enum.map(fn point -> {map_get_any(point, "x") || 0, map_get_any(point, "y") || 0} end)

    case coords do
      [] ->
        nil

      _ ->
        xs = Enum.map(coords, fn {x, _y} -> x + ox end)
        ys = Enum.map(coords, fn {_x, y} -> y + oy end)
        min_x = Enum.min(xs)
        max_x = Enum.max(xs)
        min_y = Enum.min(ys)
        max_y = Enum.max(ys)
        bounds_map(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
    end
  end

  defp compact_op_bounds(_op), do: nil

  @spec op_hash(compact_scene_op() | svg_op()) :: String.t() | nil
  defp op_hash(%{hash: hash}), do: hash
  defp op_hash(%{"hash" => hash}), do: hash
  defp op_hash(_), do: nil

  @spec op_bounds(compact_scene_op() | svg_op() | nil) :: bounds_map() | nil
  defp op_bounds(%{bounds: bounds}), do: bounds
  defp op_bounds(%{"bounds" => bounds}), do: bounds
  defp op_bounds(_), do: nil

  @spec merge_dirty_bounds([bounds_map()]) :: [bounds_map()]
  defp merge_dirty_bounds([]), do: []

  defp merge_dirty_bounds(bounds) when is_list(bounds) do
    Enum.map(bounds, fn bounds ->
      %{
        x: Map.get(bounds, :x, Map.get(bounds, "x", 0)),
        y: Map.get(bounds, :y, Map.get(bounds, "y", 0)),
        w: Map.get(bounds, :w, Map.get(bounds, "w", 0)),
        h: Map.get(bounds, :h, Map.get(bounds, "h", 0))
      }
    end)
  end

  @spec bounds_map(wire_value(), wire_value(), wire_value(), wire_value()) :: bounds_map()
  defp bounds_map(x, y, w, h), do: %{x: x || 0, y: y || 0, w: max(w || 0, 0), h: max(h || 0, 0)}

  @spec stable_hash(hash_input()) :: String.t()
  defp stable_hash(value) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary(value))
    |> Base.encode16(case: :lower)
  end

  @spec map_get_any(PreviewTypes.wire_map() | nil, String.t()) :: wire_value()
  defp map_get_any(map, key), do: Wire.map_get_any(map, key)
end
