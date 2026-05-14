defmodule IdeWeb.WorkspaceLive.DebuggerPreview do
  @moduledoc false

  @default_screen_w 144
  @default_screen_h 168

  @spec screen_dimensions(term(), term()) :: {pos_integer(), pos_integer()}
  def screen_dimensions(runtime, tree \\ nil) do
    raw_model = raw_runtime_model(runtime)
    model = runtime_model(runtime)

    launch =
      first_map([map_get_any(model, "launch_context"), map_get_any(raw_model, "launch_context")])

    launch_screen = first_map([map_get_any(launch, "screen")])
    tree_box = if is_map(tree), do: first_map([map_get_any(tree, "box")]), else: %{}

    width =
      first_present([
        map_get_any(launch_screen, "width"),
        map_get_any(tree_box, "w")
      ])

    height =
      first_present([
        map_get_any(launch_screen, "height"),
        map_get_any(tree_box, "h")
      ])

    {dimension_int(width, @default_screen_w), dimension_int(height, @default_screen_h)}
  end

  @spec screen_round?(term(), term()) :: boolean()
  def screen_round?(runtime, tree \\ nil) do
    raw_model = raw_runtime_model(runtime)
    model = runtime_model(runtime)

    launch =
      first_map([map_get_any(model, "launch_context"), map_get_any(raw_model, "launch_context")])

    launch_screen = first_map([map_get_any(launch, "screen")])

    round? =
      first_present([
        map_get_any(launch_screen, "isRound")
      ])

    shape =
      if is_map(tree) do
        map_get_any(tree, "shape")
      end

    boolean_value?(round?) || shape == "round"
  end

  @spec svg_ops(term(), term()) :: term()
  def svg_ops(tree, runtime) when is_map(tree) do
    runtime_ops = runtime_compact_scene_output(runtime)

    if runtime_ops != [] do
      runtime_ops
    else
      model = runtime_model(runtime)
      primary_int = primary_int_model_value(model)

      tree
      |> collect_view_nodes()
      |> Enum.flat_map(&svg_op_from_node(&1, primary_int, model))
      |> apply_svg_style_state()
    end
  end

  def svg_ops(_tree, runtime), do: runtime_compact_scene_output(runtime)

  @spec compact_scene(term()) :: map()
  def compact_scene(runtime) when is_map(runtime) do
    model = Map.get(runtime, :model) || Map.get(runtime, "model") || %{}

    case Map.get(model, "compact_scene") || Map.get(model, :compact_scene) ||
           Map.get(model, "runtime_compact_scene") || Map.get(model, :runtime_compact_scene) do
      scene when is_map(scene) ->
        normalize_compact_scene(scene)

      _ ->
        ops =
          model
          |> runtime_view_output_rows()
          |> Enum.map(&normalize_svg_op/1)
          |> Enum.reject(&is_nil/1)

        build_compact_scene(ops)
    end
  end

  def compact_scene(_runtime), do: build_compact_scene([])

  @spec compact_scene_diff(term(), term()) :: map()
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

  @spec unresolved_summary(term()) :: term()
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

  @spec display_node_type(term()) :: String.t()
  defp display_node_type(value) when is_binary(value), do: value
  defp display_node_type(_), do: "node"

  @spec arc_path(term()) :: term()
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

  @spec runtime_model(term()) :: term()
  def runtime_model(runtime) when is_map(runtime) do
    model = raw_runtime_model(runtime)
    runtime_model = Map.get(model, "runtime_model") || Map.get(model, :runtime_model)
    if is_map(runtime_model), do: runtime_model, else: model
  end

  def runtime_model(_runtime), do: %{}

  @spec raw_runtime_model(term()) :: term()
  defp raw_runtime_model(runtime) when is_map(runtime) do
    Map.get(runtime, :model) || Map.get(runtime, "model") || %{}
  end

  defp raw_runtime_model(_runtime), do: %{}

  @spec first_map([term()]) :: map()
  defp first_map(values) when is_list(values) do
    Enum.find(values, %{}, &is_map/1)
  end

  @spec first_present([term()]) :: term()
  defp first_present(values) when is_list(values) do
    Enum.find(values, fn value -> not is_nil(value) end)
  end

  @spec map_get_any(term(), String.t()) :: term()
  defp map_get_any(map, key) when is_map(map) and is_binary(key) do
    case Map.fetch(map, key) do
      {:ok, value} ->
        value

      :error ->
        map_value_by_atom_name(map, key)
    end
  end

  defp map_get_any(_map, _key), do: nil

  @spec map_value_by_atom_name(map(), String.t()) :: term()
  defp map_value_by_atom_name(map, key) when is_map(map) and is_binary(key) do
    Enum.find_value(map, fn
      {atom_key, value} when is_atom(atom_key) ->
        if Atom.to_string(atom_key) == key, do: value, else: nil

      _ ->
        nil
    end)
  end

  @spec dimension_int(term(), pos_integer()) :: pos_integer()
  defp dimension_int(value, _fallback) when is_integer(value) and value > 0, do: value

  defp dimension_int(value, _fallback) when is_float(value) and value > 0,
    do: max(1, trunc(value))

  defp dimension_int(value, fallback) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> fallback
    end
  end

  defp dimension_int(_value, fallback), do: fallback

  @spec boolean_value?(term()) :: boolean()
  defp boolean_value?(value) when value in [true, 1, "true", "True", "TRUE"], do: true
  defp boolean_value?(_value), do: false

  @spec primary_int_model_value(term()) :: term()
  def primary_int_model_value(model) when is_map(model) do
    ints =
      model
      |> Map.values()
      |> Enum.filter(&is_integer/1)

    case ints do
      [value] -> value
      _ -> nil
    end
  end

  def primary_int_model_value(_model), do: nil

  @spec text_label_from_node(term(), term()) :: term()
  def text_label_from_node(node, model \\ %{})

  def text_label_from_node(node, model) when is_map(node) and is_map(model) do
    env = %{"model" => model}

    text =
      case node_children(node) do
        [_font_node, _pos_node, label_node | _] ->
          resolve_text_label_value(label_node, env)

        _ ->
          resolve_text_label_value(node, env)
      end

    if is_binary(text) and String.trim(text) != "", do: text, else: "Label"
  end

  def text_label_from_node(_node, _model), do: "Label"

  @spec resolve_text_label_value(term(), map()) :: String.t() | nil
  defp resolve_text_label_value(node, env) when is_map(node) and is_map(env) do
    value = Map.get(node, "value") || Map.get(node, :value)
    op = (Map.get(node, "op") || Map.get(node, :op) || "") |> to_string()
    type = (Map.get(node, "type") || Map.get(node, :type) || "") |> to_string()
    label = (Map.get(node, "label") || Map.get(node, :label) || "") |> to_string()

    cond do
      label == "__append__" ->
        values = node_children(node) |> Enum.map(&resolve_text_label_value(&1, env))

        if values != [] and Enum.all?(values, &is_binary/1) do
          Enum.join(values, "")
        end

      string_from_int_node?(node) ->
        node_children(node)
        |> List.first()
        |> resolve_raw_value(env)
        |> normalize_text_value()

      normalize_text_value(value) != nil ->
        normalize_text_value(value)

      op == "field_access" ->
        resolve_field_access_text(node, env)

      type == "var" and label != "" ->
        env
        |> map_value_by_key(label)
        |> normalize_text_value()

      true ->
        node_children(node)
        |> Enum.find_value(&resolve_text_label_value(&1, env))
    end
  end

  defp resolve_text_label_value(_node, _env), do: nil

  @spec string_from_int_node?(map()) :: boolean()
  defp string_from_int_node?(node) when is_map(node) do
    target =
      to_string(Map.get(node, "qualified_target") || Map.get(node, :qualified_target) || "")

    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "")

    target in ["String.fromInt", "Basics.String.fromInt"] or type == "fromInt"
  end

  @spec resolve_field_access_text(map(), map()) :: String.t() | nil
  defp resolve_field_access_text(node, env) when is_map(node) and is_map(env) do
    label = (Map.get(node, "label") || Map.get(node, :label) || "") |> to_string()

    field =
      (Map.get(node, "field") || Map.get(node, :field) ||
         label |> String.split(".") |> List.last())
      |> to_string()

    source_value =
      case node_children(node) do
        [source_node | _] ->
          resolve_raw_value(source_node, env)

        _ ->
          if String.contains?(label, ".") do
            source_name = label |> String.split(".") |> List.first()
            map_value_by_key(env, source_name)
          else
            nil
          end
      end

    source_value
    |> case do
      map when is_map(map) -> map_value_by_key(map, field)
      _ -> nil
    end
    |> normalize_text_value()
  end

  defp resolve_field_access_text(_node, _env), do: nil

  @spec resolve_raw_value(term(), map()) :: term()
  defp resolve_raw_value(node, env) when is_map(node) and is_map(env) do
    value = Map.get(node, "value") || Map.get(node, :value)
    type = (Map.get(node, "type") || Map.get(node, :type) || "") |> to_string()
    label = (Map.get(node, "label") || Map.get(node, :label) || "") |> to_string()
    op = (Map.get(node, "op") || Map.get(node, :op) || "") |> to_string()

    cond do
      not is_nil(value) ->
        value

      op == "field_access" ->
        resolve_field_access_text(node, env)

      type == "var" and label != "" ->
        map_value_by_key(env, label)

      true ->
        nil
    end
  end

  defp resolve_raw_value(_node, _env), do: nil

  @spec normalize_text_value(term()) :: String.t() | nil
  defp normalize_text_value(value) when is_binary(value) do
    if String.trim(value) != "", do: value, else: nil
  end

  defp normalize_text_value(value) when is_integer(value), do: Integer.to_string(value)

  defp normalize_text_value(value) when is_float(value),
    do: :erlang.float_to_binary(value, [:compact])

  defp normalize_text_value(_value), do: nil

  @spec map_value_by_key(map(), String.t()) :: term()
  defp map_value_by_key(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) ||
      Enum.find_value(map, fn
        {atom_key, value} when is_atom(atom_key) ->
          if Atom.to_string(atom_key) == key, do: value, else: nil

        _ ->
          nil
      end)
  end

  @spec pebble_angle_to_rad(term()) :: term()
  defp pebble_angle_to_rad(angle) when is_integer(angle) do
    angle * 2.0 * :math.pi() / 65_536.0 - :math.pi() / 2.0
  end

  defp pebble_angle_to_rad(_), do: -:math.pi() / 2.0

  @spec runtime_compact_scene_output(term()) :: [map()]
  defp runtime_compact_scene_output(runtime) do
    runtime
    |> compact_scene()
    |> Map.get(:ops, [])
    |> Enum.map(&Map.get(&1, :op))
    |> Enum.filter(&is_map/1)
    |> apply_svg_style_state()
  end

  @spec runtime_view_output_rows(map()) :: [map()]
  defp runtime_view_output_rows(model) when is_map(model) do
    model
    |> Map.get("runtime_view_output", Map.get(model, :runtime_view_output, []))
    |> List.wrap()
    |> Enum.filter(&is_map/1)
  end

  @spec normalize_compact_scene(map()) :: map()
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

  @spec normalize_compact_scene_map(term()) :: map()
  defp normalize_compact_scene_map(%{version: _, ops: _} = scene),
    do: normalize_compact_scene(scene)

  defp normalize_compact_scene_map(%{"version" => _, "ops" => _} = scene),
    do: normalize_compact_scene(scene)

  defp normalize_compact_scene_map(%{ops: _} = scene), do: normalize_compact_scene(scene)
  defp normalize_compact_scene_map(%{"ops" => _} = scene), do: normalize_compact_scene(scene)
  defp normalize_compact_scene_map(runtime) when is_map(runtime), do: compact_scene(runtime)
  defp normalize_compact_scene_map(_), do: build_compact_scene([])

  @spec build_compact_scene([map()]) :: map()
  defp build_compact_scene(ops) when is_list(ops) do
    rows =
      Enum.map(ops, fn op ->
        %{op: op, bounds: compact_op_bounds(op), hash: stable_hash(op)}
      end)

    %{version: 1, ops: rows, hash: stable_hash(Enum.map(rows, & &1.hash))}
  end

  @spec atomize_known_op(map()) :: map()
  defp atomize_known_op(op) when is_map(op) do
    Enum.reduce(op, %{}, fn
      {"kind", value}, acc -> Map.put(acc, :kind, normalize_kind_atom(value))
      {key, value}, acc when is_binary(key) -> Map.put(acc, compact_key_atom(key) || key, value)
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  @spec normalize_kind_atom(term()) :: atom() | term()
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
      "text_int" -> :text_int
      "text_label" -> :text_label
      "text" -> :text
      "unresolved" -> :unresolved
      _ -> nil
    end
  end

  @spec compact_op_bounds(map()) :: map() | nil
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
              :text_label
            ] do
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

  @spec op_hash(term()) :: term()
  defp op_hash(%{hash: hash}), do: hash
  defp op_hash(%{"hash" => hash}), do: hash
  defp op_hash(_), do: nil

  @spec op_bounds(term()) :: term()
  defp op_bounds(%{bounds: bounds}), do: bounds
  defp op_bounds(%{"bounds" => bounds}), do: bounds
  defp op_bounds(_), do: nil

  @spec merge_dirty_bounds([map()]) :: [map()]
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

  @spec bounds_map(term(), term(), term(), term()) :: map()
  defp bounds_map(x, y, w, h), do: %{x: x || 0, y: y || 0, w: max(w || 0, 0), h: max(h || 0, 0)}

  @spec stable_hash(term()) :: String.t()
  defp stable_hash(value) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary(value))
    |> Base.encode16(case: :lower)
  end

  @spec normalize_svg_op(term()) :: term()
  defp normalize_svg_op(op) when is_map(op) do
    kind = to_string(Map.get(op, "kind") || Map.get(op, :kind) || "")

    normalized =
      case kind do
        "push_context" ->
          %{kind: :push_context}

        "pop_context" ->
          %{kind: :pop_context}

        "stroke_width" ->
          case map_integer_required(op, "value") do
            {:ok, value} -> %{kind: :stroke_width, value: max(value, 1)}
            :error -> unresolved_svg_op("stroke_width", ["value"], op)
          end

        "antialiased" ->
          case map_integer_required(op, "value") do
            {:ok, value} -> %{kind: :antialiased, value: value != 0}
            :error -> unresolved_svg_op("antialiased", ["value"], op)
          end

        "stroke_color" ->
          normalize_style_color_op(:stroke_color, op, "stroke_color")

        "fill_color" ->
          normalize_style_color_op(:fill_color, op, "fill_color")

        "text_color" ->
          normalize_style_color_op(:text_color, op, "text_color")

        "compositing_mode" ->
          case map_integer_required(op, "value") do
            {:ok, value} -> %{kind: :compositing_mode, value: value}
            :error -> unresolved_svg_op("compositing_mode", ["value"], op)
          end

        "clear" ->
          case map_integer_required(op, "color") do
            {:ok, color} -> %{kind: :clear, color: color}
            :error -> unresolved_svg_op("clear", ["color"], op)
          end

        "round_rect" ->
          case map_integers_required(op, ["x", "y", "w", "h", "radius", "fill"]) do
            {:ok, [x, y, w, h, radius, fill]} ->
              %{kind: :round_rect, x: x, y: y, w: w, h: h, radius: radius, fill: fill}

            :error ->
              unresolved_svg_op("round_rect", ["x", "y", "w", "h", "radius", "fill"], op)
          end

        "rect" ->
          case map_integers_required(op, ["x", "y", "w", "h", "fill"]) do
            {:ok, [x, y, w, h, fill]} -> %{kind: :rect, x: x, y: y, w: w, h: h, fill: fill}
            :error -> unresolved_svg_op("rect", ["x", "y", "w", "h", "fill"], op)
          end

        "fill_rect" ->
          case map_integers_required(op, ["x", "y", "w", "h", "fill"]) do
            {:ok, [x, y, w, h, fill]} -> %{kind: :fill_rect, x: x, y: y, w: w, h: h, fill: fill}
            :error -> unresolved_svg_op("fill_rect", ["x", "y", "w", "h", "fill"], op)
          end

        "line" ->
          case map_integers_required(op, ["x1", "y1", "x2", "y2", "color"]) do
            {:ok, [x1, y1, x2, y2, color]} ->
              %{kind: :line, x1: x1, y1: y1, x2: x2, y2: y2, color: color}

            :error ->
              unresolved_svg_op("line", ["x1", "y1", "x2", "y2", "color"], op)
          end

        "arc" ->
          case map_integers_required(op, ["x", "y", "w", "h", "start_angle", "end_angle"]) do
            {:ok, [x, y, w, h, start_angle, end_angle]} ->
              %{
                kind: :arc,
                x: x,
                y: y,
                w: w,
                h: h,
                start_angle: start_angle,
                end_angle: end_angle
              }

            :error ->
              unresolved_svg_op("arc", ["x", "y", "w", "h", "start_angle", "end_angle"], op)
          end

        "fill_radial" ->
          case map_integers_required(op, ["x", "y", "w", "h", "start_angle", "end_angle"]) do
            {:ok, [x, y, w, h, start_angle, end_angle]} ->
              %{
                kind: :fill_radial,
                x: x,
                y: y,
                w: w,
                h: h,
                start_angle: start_angle,
                end_angle: end_angle
              }

            :error ->
              unresolved_svg_op(
                "fill_radial",
                ["x", "y", "w", "h", "start_angle", "end_angle"],
                op
              )
          end

        "path_filled" ->
          case map_path_required(op) do
            {:ok, path} ->
              Map.put(path, :kind, :path_filled)

            :error ->
              unresolved_svg_op("path_filled", ["points", "offset_x", "offset_y", "rotation"], op)
          end

        "path_outline" ->
          case map_path_required(op) do
            {:ok, path} ->
              Map.put(path, :kind, :path_outline)

            :error ->
              unresolved_svg_op(
                "path_outline",
                ["points", "offset_x", "offset_y", "rotation"],
                op
              )
          end

        "path_outline_open" ->
          case map_path_required(op) do
            {:ok, path} ->
              Map.put(path, :kind, :path_outline_open)

            :error ->
              unresolved_svg_op(
                "path_outline_open",
                ["points", "offset_x", "offset_y", "rotation"],
                op
              )
          end

        "circle" ->
          case map_integers_required(op, ["cx", "cy", "r", "color"]) do
            {:ok, [cx, cy, r, color]} -> %{kind: :circle, cx: cx, cy: cy, r: r, color: color}
            :error -> unresolved_svg_op("circle", ["cx", "cy", "r", "color"], op)
          end

        "fill_circle" ->
          case map_integers_required(op, ["cx", "cy", "r", "color"]) do
            {:ok, [cx, cy, r, color]} -> %{kind: :fill_circle, cx: cx, cy: cy, r: r, color: color}
            :error -> unresolved_svg_op("fill_circle", ["cx", "cy", "r", "color"], op)
          end

        "pixel" ->
          case map_integers_required(op, ["x", "y", "color"]) do
            {:ok, [x, y, color]} -> %{kind: :pixel, x: x, y: y, color: color}
            :error -> unresolved_svg_op("pixel", ["x", "y", "color"], op)
          end

        "bitmap_in_rect" ->
          case map_integers_required(op, ["bitmap_id", "x", "y", "w", "h"]) do
            {:ok, [bitmap_id, x, y, w, h]} ->
              %{kind: :bitmap_in_rect, bitmap_id: bitmap_id, x: x, y: y, w: w, h: h}

            :error ->
              unresolved_svg_op("bitmap_in_rect", ["bitmap_id", "x", "y", "w", "h"], op)
          end

        "rotated_bitmap" ->
          case map_integers_required(op, [
                 "bitmap_id",
                 "src_w",
                 "src_h",
                 "angle",
                 "center_x",
                 "center_y"
               ]) do
            {:ok, [bitmap_id, src_w, src_h, angle, center_x, center_y]} ->
              %{
                kind: :rotated_bitmap,
                bitmap_id: bitmap_id,
                src_w: src_w,
                src_h: src_h,
                angle: angle,
                center_x: center_x,
                center_y: center_y
              }

            :error ->
              unresolved_svg_op(
                "rotated_bitmap",
                ["bitmap_id", "src_w", "src_h", "angle", "center_x", "center_y"],
                op
              )
          end

        "text_int" ->
          case map_integers_required(op, ["x", "y"]) do
            {:ok, [x, y]} ->
              text = to_string(Map.get(op, "text") || Map.get(op, :text) || "")

              if text == "",
                do: unresolved_svg_op("text_int", ["x", "y", "text"], op),
                else: %{kind: :text_int, x: x, y: y, text: text}

            :error ->
              unresolved_svg_op("text_int", ["x", "y", "text"], op)
          end

        "text_label" ->
          case map_integers_required(op, ["x", "y"]) do
            {:ok, [x, y]} ->
              text = to_string(Map.get(op, "text") || Map.get(op, :text) || "")

              if text == "",
                do: unresolved_svg_op("text_label", ["x", "y", "text"], op),
                else: %{kind: :text_label, x: x, y: y, text: text}

            :error ->
              unresolved_svg_op("text_label", ["x", "y", "text"], op)
          end

        "text" ->
          case map_integers_required(op, ["x", "y"]) do
            {:ok, [x, y]} ->
              text = to_string(Map.get(op, "text") || Map.get(op, :text) || "")

              if text == "",
                do: unresolved_svg_op("text", ["x", "y", "text"], op),
                else: text_box_svg_op(op, x, y, text)

            :error ->
              unresolved_svg_op("text", ["x", "y", "text"], op)
          end

        "unresolved" ->
          unresolved_svg_op(
            to_string(Map.get(op, "node_type") || Map.get(op, :node_type) || "node"),
            [],
            op
          )

        _ ->
          nil
      end

    maybe_put_svg_source(normalized, op)
  end

  defp normalize_svg_op(_op), do: nil

  @spec maybe_put_svg_source(term(), map()) :: term()
  defp maybe_put_svg_source(%{} = normalized, original) when is_map(original) do
    case Map.get(original, "source") || Map.get(original, :source) do
      %{} = source -> Map.put(normalized, :source, source)
      _ -> normalized
    end
  end

  defp maybe_put_svg_source(normalized, _original), do: normalized

  @spec text_box_svg_op(map(), integer(), integer(), String.t()) :: map()
  defp text_box_svg_op(op, x, y, text) when is_map(op) and is_integer(x) and is_integer(y) do
    base = %{kind: :text_label, x: x, y: y, text: text}

    case map_integers_required(op, ["w", "h"]) do
      {:ok, [w, h]} -> Map.merge(base, %{w: w, h: h, text_align: "center", font_size: h})
      :error -> base
    end
  end

  @spec normalize_style_color_op(atom(), map(), String.t(), String.t()) :: map()
  defp normalize_style_color_op(kind, op, node_type, value_key \\ "color")
       when is_atom(kind) and is_map(op) and is_binary(node_type) and is_binary(value_key) do
    value =
      case map_integer_required(op, value_key) do
        {:ok, color} ->
          {:ok, color}

        :error when value_key == "color" ->
          map_integer_required(op, "value")

        :error ->
          :error
      end

    case value do
      {:ok, color} -> %{kind: kind, color: color}
      :error -> unresolved_svg_op(node_type, [value_key], op)
    end
  end

  @spec apply_svg_style_state([map()]) :: [map()]
  defp apply_svg_style_state(ops) when is_list(ops) do
    {rows, _stack} =
      Enum.reduce(ops, {[], [default_svg_style()]}, fn op, {rows, stack} ->
        style = List.first(stack) || default_svg_style()

        case op.kind do
          :push_context ->
            {rows, [style | stack]}

          :pop_context ->
            {rows, pop_svg_style(stack)}

          :stroke_width ->
            {rows, update_svg_style(stack, :stroke_width, op.value)}

          :antialiased ->
            {rows, update_svg_style(stack, :antialiased, op.value)}

          :stroke_color ->
            {rows, update_svg_style(stack, :stroke_color, op.color)}

          :fill_color ->
            {rows, update_svg_style(stack, :fill_color, op.color)}

          :text_color ->
            {rows, update_svg_style(stack, :text_color, op.color)}

          :compositing_mode ->
            {rows, update_svg_style(stack, :compositing_mode, op.value)}

          _ ->
            {[apply_svg_style(op, style) | rows], stack}
        end
      end)

    Enum.reverse(rows)
  end

  @spec default_svg_style() :: map()
  defp default_svg_style do
    %{
      stroke_color: nil,
      fill_color: nil,
      text_color: nil,
      stroke_width: 1,
      antialiased: true,
      compositing_mode: 0
    }
  end

  @spec pop_svg_style([map()]) :: [map()]
  defp pop_svg_style([_current, parent | rest]), do: [parent | rest]
  defp pop_svg_style(stack), do: stack

  @spec update_svg_style([map()], atom(), term()) :: [map()]
  defp update_svg_style([style | rest], key, value), do: [Map.put(style, key, value) | rest]
  defp update_svg_style([], key, value), do: [Map.put(default_svg_style(), key, value)]

  @spec apply_svg_style(map(), map()) :: map()
  defp apply_svg_style(%{kind: :unresolved} = op, _style), do: op

  defp apply_svg_style(%{kind: :clear} = op, _style), do: op

  defp apply_svg_style(%{kind: kind} = op, style)
       when kind in [
              :line,
              :rect,
              :round_rect,
              :arc,
              :path_outline,
              :path_outline_open,
              :circle,
              :pixel
            ] do
    op
    |> Map.put(
      :stroke_color,
      style_color(style, :stroke_color, Map.get(op, :color) || Map.get(op, :fill))
    )
    |> Map.put(:stroke_width, style.stroke_width || 1)
    |> put_common_svg_style(style)
  end

  defp apply_svg_style(%{kind: kind} = op, style)
       when kind in [:fill_rect, :fill_circle, :path_filled, :fill_radial] do
    op
    |> Map.put(
      :fill_color,
      style_color(style, :fill_color, Map.get(op, :color) || Map.get(op, :fill))
    )
    |> Map.put(
      :stroke_color,
      style_color(style, :stroke_color, Map.get(op, :color) || Map.get(op, :fill))
    )
    |> Map.put(:stroke_width, style.stroke_width || 1)
    |> put_common_svg_style(style)
  end

  defp apply_svg_style(%{kind: kind} = op, style) when kind in [:text_int, :text_label] do
    op
    |> Map.put(:text_color, style_color(style, :text_color, Map.get(op, :color)))
    |> put_common_svg_style(style)
  end

  defp apply_svg_style(op, style), do: put_common_svg_style(op, style)

  @spec put_common_svg_style(map(), map()) :: map()
  defp put_common_svg_style(op, style) do
    op
    |> Map.put(:antialiased, style.antialiased)
    |> Map.put(:compositing_mode, style.compositing_mode)
  end

  @spec style_color(map(), atom(), term()) :: term()
  defp style_color(style, key, fallback), do: Map.get(style, key) || fallback

  @spec map_integer_required(term(), term()) :: term()
  defp map_integer_required(map, key) when is_map(map) and is_binary(key) do
    value = map_integer(map, key, :__missing__)
    if is_integer(value), do: {:ok, value}, else: :error
  end

  defp map_integer_required(_map, _key), do: :error

  @spec map_integers_required(term(), term()) :: term()
  defp map_integers_required(map, keys) when is_map(map) and is_list(keys) do
    values = Enum.map(keys, &map_integer_required(map, &1))

    if Enum.all?(values, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(values, fn {:ok, v} -> v end)}
    else
      :error
    end
  end

  defp map_integers_required(_map, _keys), do: :error

  @spec map_path_required(term()) :: term()
  defp map_path_required(map) when is_map(map) do
    with {:ok, points} <- map_points_required(map),
         {:ok, offset_x} <- map_integer_required(map, "offset_x"),
         {:ok, offset_y} <- map_integer_required(map, "offset_y"),
         {:ok, rotation} <- map_integer_required(map, "rotation") do
      {:ok, %{points: points, offset_x: offset_x, offset_y: offset_y, rotation: rotation}}
    else
      _ -> :error
    end
  end

  @spec map_points_required(term()) :: term()
  defp map_points_required(map) when is_map(map) do
    points = Map.get(map, "points") || Map.get(map, :points)

    cond do
      is_list(points) and points != [] ->
        normalized =
          points
          |> Enum.map(&normalize_point_pair/1)

        if Enum.all?(normalized, &match?({:ok, _}, &1)) do
          {:ok, Enum.map(normalized, fn {:ok, pair} -> pair end)}
        else
          :error
        end

      true ->
        :error
    end
  end

  @spec normalize_point_pair(term()) :: term()
  defp normalize_point_pair([x, y]) when is_integer(x) and is_integer(y), do: {:ok, [x, y]}
  defp normalize_point_pair({x, y}) when is_integer(x) and is_integer(y), do: {:ok, [x, y]}

  defp normalize_point_pair(%{"x" => x, "y" => y}) when is_integer(x) and is_integer(y),
    do: {:ok, [x, y]}

  defp normalize_point_pair(%{x: x, y: y}) when is_integer(x) and is_integer(y), do: {:ok, [x, y]}
  defp normalize_point_pair(_), do: :error

  @spec unresolved_svg_op(term(), term(), term()) :: term()
  defp unresolved_svg_op(node_type, required_keys, op) do
    %{
      kind: :unresolved,
      node_type: to_string(node_type),
      required_keys: required_keys,
      provided_int_count: map_integer(op, "provided_int_count", 0),
      required_int_count: map_integer(op, "required_int_count", length(required_keys))
    }
  end

  @spec map_integer(term(), term(), term()) :: term()
  defp map_integer(map, key, fallback) when is_map(map) and is_binary(key) do
    atom_key =
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
        "radius" -> :radius
        "fill" -> :fill
        "color" -> :color
        "value" -> :value
        "p0" -> :p0
        "start_angle" -> :start_angle
        "end_angle" -> :end_angle
        "provided_int_count" -> :provided_int_count
        "required_int_count" -> :required_int_count
        "offset_x" -> :offset_x
        "offset_y" -> :offset_y
        "rotation" -> :rotation
        "bitmap_id" -> :bitmap_id
        "src_w" -> :src_w
        "src_h" -> :src_h
        "angle" -> :angle
        "center_x" -> :center_x
        "center_y" -> :center_y
        _ -> nil
      end

    value = Map.get(map, key) || Map.get(map, atom_key)

    cond do
      is_integer(value) ->
        value

      is_float(value) ->
        trunc(value)

      is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} -> parsed
          _ -> fallback
        end

      true ->
        fallback
    end
  end

  @spec collect_view_nodes(term()) :: term()
  defp collect_view_nodes(node) when is_map(node) do
    type = node |> Map.get("type", Map.get(node, :type, "")) |> to_string()

    cond do
      type == "if" ->
        []

      type == "group" ->
        collect_group_view_nodes(node)

      true ->
        collect_view_nodes_in_node(node, type)
    end
  end

  defp collect_view_nodes(_), do: []

  @spec collect_group_view_nodes(map()) :: [map()]
  defp collect_group_view_nodes(node) when is_map(node) do
    children =
      node
      |> node_children()
      |> Enum.flat_map(&collect_view_nodes/1)

    [%{"type" => "push_context"}] ++
      group_style_nodes(node) ++ children ++ [%{"type" => "pop_context"}]
  end

  @spec group_style_nodes(map()) :: [map()]
  defp group_style_nodes(node) when is_map(node) do
    style =
      case Map.get(node, "style") || Map.get(node, :style) do
        %{} = value -> value
        _ -> %{}
      end

    [
      style_node(style, "stroke_color"),
      style_node(style, "fill_color"),
      style_node(style, "text_color")
    ]
    |> Enum.reject(&is_nil/1)
  end

  @spec style_node(map(), String.t()) :: map() | nil
  defp style_node(style, key) when is_map(style) and is_binary(key) do
    case Map.get(style, key) || Map.get(style, String.to_atom(key)) do
      value when is_integer(value) -> %{"type" => key, "color" => value}
      _ -> nil
    end
  end

  @spec collect_view_nodes_in_node(map(), String.t()) :: [map()]
  defp collect_view_nodes_in_node(node, type) when is_map(node) and is_binary(type) do
    children =
      case node["children"] || node[:children] do
        list when is_list(list) -> list
        _ -> []
      end

    here = if type != "", do: [node], else: []
    child_nodes = children |> Enum.filter(&is_map/1) |> Enum.flat_map(&collect_view_nodes/1)
    here ++ child_nodes
  end

  @spec svg_op_from_node(term(), term(), term()) :: term()
  defp svg_op_from_node(node, primary_int, model) when is_map(node) do
    type = node |> Map.get("type", Map.get(node, :type, "")) |> to_string()
    ints = node_int_args(node, model)

    case concrete_svg_op_from_node(node) do
      %{} = op ->
        [op]

      nil ->
        svg_op_from_node_children(node, type, ints, primary_int, model)
    end
  end

  defp svg_op_from_node(_node, _primary_int, _model), do: []

  @spec concrete_svg_op_from_node(map()) :: map() | nil
  defp concrete_svg_op_from_node(node) when is_map(node) do
    type = node |> Map.get("type", Map.get(node, :type, "")) |> to_string()

    op =
      case type do
        "push_context" ->
          %{"kind" => "push_context"}

        "pop_context" ->
          %{"kind" => "pop_context"}

        "stroke_color" ->
          %{"kind" => "stroke_color", "color" => Map.get(node, "color") || Map.get(node, :color)}

        "fill_color" ->
          %{"kind" => "fill_color", "color" => Map.get(node, "color") || Map.get(node, :color)}

        "text_color" ->
          %{"kind" => "text_color", "color" => Map.get(node, "color") || Map.get(node, :color)}

        "clear" ->
          %{"kind" => "clear", "color" => Map.get(node, "color") || Map.get(node, :color)}

        "roundRect" ->
          %{
            "kind" => "round_rect",
            "x" => Map.get(node, "x") || Map.get(node, :x),
            "y" => Map.get(node, "y") || Map.get(node, :y),
            "w" => Map.get(node, "w") || Map.get(node, :w),
            "h" => Map.get(node, "h") || Map.get(node, :h),
            "radius" => Map.get(node, "radius") || Map.get(node, :radius),
            "fill" =>
              Map.get(node, "fill") || Map.get(node, :fill) || Map.get(node, "color") ||
                Map.get(node, :color)
          }

        "rect" ->
          %{
            "kind" => "rect",
            "x" => Map.get(node, "x") || Map.get(node, :x),
            "y" => Map.get(node, "y") || Map.get(node, :y),
            "w" => Map.get(node, "w") || Map.get(node, :w),
            "h" => Map.get(node, "h") || Map.get(node, :h),
            "fill" =>
              Map.get(node, "fill") || Map.get(node, :fill) || Map.get(node, "color") ||
                Map.get(node, :color)
          }

        "fillRect" ->
          %{
            "kind" => "fill_rect",
            "x" => Map.get(node, "x") || Map.get(node, :x),
            "y" => Map.get(node, "y") || Map.get(node, :y),
            "w" => Map.get(node, "w") || Map.get(node, :w),
            "h" => Map.get(node, "h") || Map.get(node, :h),
            "fill" =>
              Map.get(node, "fill") || Map.get(node, :fill) || Map.get(node, "color") ||
                Map.get(node, :color)
          }

        "line" ->
          %{
            "kind" => "line",
            "x1" => Map.get(node, "x1") || Map.get(node, :x1),
            "y1" => Map.get(node, "y1") || Map.get(node, :y1),
            "x2" => Map.get(node, "x2") || Map.get(node, :x2),
            "y2" => Map.get(node, "y2") || Map.get(node, :y2),
            "color" => Map.get(node, "color") || Map.get(node, :color)
          }

        "arc" ->
          %{
            "kind" => "arc",
            "x" => Map.get(node, "x") || Map.get(node, :x),
            "y" => Map.get(node, "y") || Map.get(node, :y),
            "w" => Map.get(node, "w") || Map.get(node, :w),
            "h" => Map.get(node, "h") || Map.get(node, :h),
            "start_angle" => Map.get(node, "start_angle") || Map.get(node, :start_angle),
            "end_angle" => Map.get(node, "end_angle") || Map.get(node, :end_angle)
          }

        "fillRadial" ->
          %{
            "kind" => "fill_radial",
            "x" => Map.get(node, "x") || Map.get(node, :x),
            "y" => Map.get(node, "y") || Map.get(node, :y),
            "w" => Map.get(node, "w") || Map.get(node, :w),
            "h" => Map.get(node, "h") || Map.get(node, :h),
            "start_angle" => Map.get(node, "start_angle") || Map.get(node, :start_angle),
            "end_angle" => Map.get(node, "end_angle") || Map.get(node, :end_angle)
          }

        "circle" ->
          %{
            "kind" => "circle",
            "cx" => Map.get(node, "cx") || Map.get(node, :cx),
            "cy" => Map.get(node, "cy") || Map.get(node, :cy),
            "r" => Map.get(node, "r") || Map.get(node, :r),
            "color" => Map.get(node, "color") || Map.get(node, :color)
          }

        "fillCircle" ->
          %{
            "kind" => "fill_circle",
            "cx" => Map.get(node, "cx") || Map.get(node, :cx),
            "cy" => Map.get(node, "cy") || Map.get(node, :cy),
            "r" => Map.get(node, "r") || Map.get(node, :r),
            "color" => Map.get(node, "color") || Map.get(node, :color)
          }

        "pixel" ->
          %{
            "kind" => "pixel",
            "x" => Map.get(node, "x") || Map.get(node, :x),
            "y" => Map.get(node, "y") || Map.get(node, :y),
            "color" => Map.get(node, "color") || Map.get(node, :color)
          }

        "bitmapInRect" ->
          %{
            "kind" => "bitmap_in_rect",
            "bitmap_id" => Map.get(node, "bitmap_id") || Map.get(node, :bitmap_id),
            "x" => Map.get(node, "x") || Map.get(node, :x),
            "y" => Map.get(node, "y") || Map.get(node, :y),
            "w" => Map.get(node, "w") || Map.get(node, :w),
            "h" => Map.get(node, "h") || Map.get(node, :h)
          }

        "text" ->
          %{
            "kind" => "text",
            "x" => Map.get(node, "x") || Map.get(node, :x),
            "y" => Map.get(node, "y") || Map.get(node, :y),
            "w" => Map.get(node, "w") || Map.get(node, :w),
            "h" => Map.get(node, "h") || Map.get(node, :h),
            "text" => Map.get(node, "text") || Map.get(node, :text)
          }

        "textInt" ->
          %{
            "kind" => "text_int",
            "x" => Map.get(node, "x") || Map.get(node, :x),
            "y" => Map.get(node, "y") || Map.get(node, :y),
            "text" =>
              Map.get(node, "text") || Map.get(node, :text) || Map.get(node, "value") ||
                Map.get(node, :value)
          }

        "textLabel" ->
          %{
            "kind" => "text_label",
            "x" => Map.get(node, "x") || Map.get(node, :x),
            "y" => Map.get(node, "y") || Map.get(node, :y),
            "text" => Map.get(node, "text") || Map.get(node, :text)
          }

        _ ->
          nil
      end

    case op do
      %{} ->
        case normalize_svg_op(op) do
          %{kind: :unresolved} = unresolved ->
            if node_children(node) == [], do: unresolved, else: nil

          normalized ->
            normalized
        end

      nil ->
        nil
    end
  end

  @spec svg_op_from_node_children(map(), String.t(), [integer()], term(), term()) :: [map()]
  defp svg_op_from_node_children(node, type, ints, primary_int, model) do
    case type do
      "clear" ->
        case require_ints(ints, 1) do
          {:ok, [color]} ->
            [%{kind: :clear, color: color}]

          :error ->
            [
              %{
                kind: :unresolved,
                node_type: "clear",
                provided_int_count: length(ints),
                required_int_count: 1
              }
            ]
        end

      "roundRect" ->
        case require_ints(ints, 6) do
          {:ok, [x, y, w, h, radius, fill]} ->
            [
              %{
                kind: :round_rect,
                x: clamp(x, 0, @default_screen_w - 1),
                y: clamp(y, 0, @default_screen_h - 1),
                w: clamp(w, 1, @default_screen_w),
                h: clamp(h, 1, @default_screen_h),
                radius: clamp(radius, 0, 80),
                fill: fill
              }
            ]

          :error ->
            [
              %{
                kind: :unresolved,
                node_type: "roundRect",
                provided_int_count: length(ints),
                required_int_count: 6
              }
            ]
        end

      "rect" ->
        case require_ints(ints, 5) do
          {:ok, [x, y, w, h, fill]} ->
            [
              %{
                kind: :rect,
                x: clamp(x, 0, @default_screen_w - 1),
                y: clamp(y, 0, @default_screen_h - 1),
                w: clamp(w, 1, @default_screen_w),
                h: clamp(h, 1, @default_screen_h),
                fill: fill
              }
            ]

          :error ->
            [
              %{
                kind: :unresolved,
                node_type: "rect",
                provided_int_count: length(ints),
                required_int_count: 5
              }
            ]
        end

      "fillRect" ->
        case require_ints(ints, 5) do
          {:ok, [x, y, w, h, fill]} ->
            [
              %{
                kind: :fill_rect,
                x: clamp(x, 0, @default_screen_w - 1),
                y: clamp(y, 0, @default_screen_h - 1),
                w: clamp(w, 1, @default_screen_w),
                h: clamp(h, 1, @default_screen_h),
                fill: fill
              }
            ]

          :error ->
            [
              %{
                kind: :unresolved,
                node_type: "fillRect",
                provided_int_count: length(ints),
                required_int_count: 5
              }
            ]
        end

      "line" ->
        case require_ints(ints, 5) do
          {:ok, [x1, y1, x2, y2, color]} ->
            [
              %{
                kind: :line,
                x1: clamp(x1, 0, @default_screen_w - 1),
                y1: clamp(y1, 0, @default_screen_h - 1),
                x2: clamp(x2, 0, @default_screen_w - 1),
                y2: clamp(y2, 0, @default_screen_h - 1),
                color: color
              }
            ]

          :error ->
            [
              %{
                kind: :unresolved,
                node_type: "line",
                provided_int_count: length(ints),
                required_int_count: 5
              }
            ]
        end

      "arc" ->
        case require_ints(ints, 6) do
          {:ok, [x, y, w, h, start_angle, end_angle]} ->
            [
              %{
                kind: :arc,
                x: clamp(x, 0, @default_screen_w - 1),
                y: clamp(y, 0, @default_screen_h - 1),
                w: clamp(w, 1, @default_screen_w),
                h: clamp(h, 1, @default_screen_h),
                start_angle: start_angle,
                end_angle: end_angle
              }
            ]

          :error ->
            [
              %{
                kind: :unresolved,
                node_type: "arc",
                provided_int_count: length(ints),
                required_int_count: 6
              }
            ]
        end

      "fillRadial" ->
        case require_ints(ints, 6) do
          {:ok, [x, y, w, h, start_angle, end_angle]} ->
            [
              %{
                kind: :fill_radial,
                x: clamp(x, 0, @default_screen_w - 1),
                y: clamp(y, 0, @default_screen_h - 1),
                w: clamp(w, 1, @default_screen_w),
                h: clamp(h, 1, @default_screen_h),
                start_angle: start_angle,
                end_angle: end_angle
              }
            ]

          :error ->
            [
              %{
                kind: :unresolved,
                node_type: "fillRadial",
                provided_int_count: length(ints),
                required_int_count: 6
              }
            ]
        end

      "pathFilled" ->
        case path_from_view_node(node) do
          {:ok, path} ->
            [
              %{
                kind: :path_filled,
                points: path.points,
                offset_x: path.offset_x,
                offset_y: path.offset_y,
                rotation: path.rotation
              }
            ]

          :error ->
            [
              %{
                kind: :unresolved,
                node_type: "pathFilled",
                provided_int_count: length(ints),
                required_int_count: 4
              }
            ]
        end

      "pathOutline" ->
        case path_from_view_node(node) do
          {:ok, path} ->
            [
              %{
                kind: :path_outline,
                points: path.points,
                offset_x: path.offset_x,
                offset_y: path.offset_y,
                rotation: path.rotation
              }
            ]

          :error ->
            [
              %{
                kind: :unresolved,
                node_type: "pathOutline",
                provided_int_count: length(ints),
                required_int_count: 4
              }
            ]
        end

      "pathOutlineOpen" ->
        case path_from_view_node(node) do
          {:ok, path} ->
            [
              %{
                kind: :path_outline_open,
                points: path.points,
                offset_x: path.offset_x,
                offset_y: path.offset_y,
                rotation: path.rotation
              }
            ]

          :error ->
            [
              %{
                kind: :unresolved,
                node_type: "pathOutlineOpen",
                provided_int_count: length(ints),
                required_int_count: 4
              }
            ]
        end

      "circle" ->
        case require_ints(ints, 4) do
          {:ok, [cx, cy, r, color]} ->
            [
              %{
                kind: :circle,
                cx: clamp(cx, 0, @default_screen_w - 1),
                cy: clamp(cy, 0, @default_screen_h - 1),
                r: clamp(r, 1, 80),
                color: color
              }
            ]

          :error ->
            [
              %{
                kind: :unresolved,
                node_type: "circle",
                provided_int_count: length(ints),
                required_int_count: 4
              }
            ]
        end

      "fillCircle" ->
        case require_ints(ints, 4) do
          {:ok, [cx, cy, r, color]} ->
            [
              %{
                kind: :fill_circle,
                cx: clamp(cx, 0, @default_screen_w - 1),
                cy: clamp(cy, 0, @default_screen_h - 1),
                r: clamp(r, 1, 80),
                color: color
              }
            ]

          :error ->
            [
              %{
                kind: :unresolved,
                node_type: "fillCircle",
                provided_int_count: length(ints),
                required_int_count: 4
              }
            ]
        end

      "pixel" ->
        case require_ints(ints, 3) do
          {:ok, [x, y, color]} ->
            [
              %{
                kind: :pixel,
                x: clamp(x, 0, @default_screen_w - 1),
                y: clamp(y, 0, @default_screen_h - 1),
                color: color
              }
            ]

          :error ->
            [
              %{
                kind: :unresolved,
                node_type: "pixel",
                provided_int_count: length(ints),
                required_int_count: 3
              }
            ]
        end

      kind when kind in ["drawBitmapInRect", "bitmapInRect"] ->
        case node_children(node) do
          [bitmap_node, bounds_node | _] ->
            with bitmap_id when is_integer(bitmap_id) <- bitmap_node_id(bitmap_node, model),
                 {:ok, [x, y, w, h]} <- rect_node_ints(bounds_node, model) do
              [
                %{
                  kind: :bitmap_in_rect,
                  bitmap_id: bitmap_id,
                  x: clamp(x, 0, @default_screen_w - 1),
                  y: clamp(y, 0, @default_screen_h - 1),
                  w: clamp(w, 1, @default_screen_w),
                  h: clamp(h, 1, @default_screen_h)
                }
              ]
            else
              _ ->
                unresolved_node("bitmapInRect", length(ints), 5)
            end

          _ ->
            unresolved_node("bitmapInRect", length(ints), 5)
        end

      "text" ->
        case node_children(node) do
          [_font_node, bounds_node, value_node | _] ->
            with {:ok, [x, y, w, h]} <- rect_node_ints(bounds_node, model) do
              [
                %{
                  kind: :text_label,
                  x: clamp(x, 0, @default_screen_w - 1),
                  y: clamp(y, 0, @default_screen_h),
                  w: clamp(w, 1, @default_screen_w),
                  h: clamp(h, 1, @default_screen_h),
                  font_size: clamp(h, 1, @default_screen_h),
                  text_align: "center",
                  text: text_label_from_node(value_node, model)
                }
              ]
            else
              _ ->
                unresolved_node("text", length(ints), 6)
            end

          _ ->
            unresolved_node("text", length(ints), 6)
        end

      "textInt" ->
        case node_children(node) do
          [_font_node, pos_node, value_node | _] ->
            with {:ok, [x, y]} <- point_pair_from_point_node(pos_node),
                 value when is_integer(value) <- node_int_value(value_node) || primary_int do
              [
                %{
                  kind: :text_int,
                  x: clamp(x, 0, @default_screen_w - 1),
                  y: clamp(y, 0, @default_screen_h),
                  text: Integer.to_string(value)
                }
              ]
            else
              _ ->
                [
                  %{
                    kind: :unresolved,
                    node_type: "textInt",
                    provided_int_count: length(ints),
                    required_int_count: 3
                  }
                ]
            end

          _ ->
            [
              %{
                kind: :unresolved,
                node_type: "textInt",
                provided_int_count: length(ints),
                required_int_count: 3
              }
            ]
        end

      "textLabel" ->
        case node_children(node) do
          [_font_node, pos_node | _] ->
            case point_pair_from_point_node(pos_node) do
              {:ok, [x, y]} ->
                [
                  %{
                    kind: :text_label,
                    x: clamp(x, 0, @default_screen_w - 1),
                    y: clamp(y, 0, @default_screen_h),
                    text: text_label_from_node(node, model)
                  }
                ]

              :error ->
                [
                  %{
                    kind: :unresolved,
                    node_type: "textLabel",
                    provided_int_count: length(ints),
                    required_int_count: 3
                  }
                ]
            end

          _ ->
            [
              %{
                kind: :unresolved,
                node_type: "textLabel",
                provided_int_count: length(ints),
                required_int_count: 3
              }
            ]
        end

      _ ->
        []
    end
  end

  @spec unresolved_node(String.t(), non_neg_integer(), pos_integer()) :: [map()]
  defp unresolved_node(node_type, provided_int_count, required_int_count) do
    [
      %{
        kind: :unresolved,
        node_type: node_type,
        provided_int_count: provided_int_count,
        required_int_count: required_int_count
      }
    ]
  end

  @spec node_int_args(map(), term()) :: [integer()]
  defp node_int_args(node, model) when is_map(node) do
    case structured_node_int_args(node, model) do
      {:ok, values} ->
        values

      :error ->
        node
        |> node_children()
        |> Enum.map(&node_int_value(&1, model))
        |> Enum.reject(&is_nil/1)
    end
  end

  @spec structured_node_int_args(map(), term()) :: {:ok, [integer()]} | :error
  defp structured_node_int_args(node, model) when is_map(node) do
    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "")
    children = node_children(node)

    case {type, children} do
      {"clear", [color_node | _]} ->
        with color when is_integer(color) <- node_color_value(color_node, model) do
          {:ok, [color]}
        else
          _ -> :error
        end

      {kind, [bounds_node, color_node | _]} when kind in ["rect", "fillRect"] ->
        with {:ok, [x, y, w, h]} <- rect_node_ints(bounds_node, model),
             color when is_integer(color) <- node_color_value(color_node, model) do
          {:ok, [x, y, w, h, color]}
        else
          _ -> :error
        end

      {"roundRect", [bounds_node, radius_node, color_node | _]} ->
        with {:ok, [x, y, w, h]} <- rect_node_ints(bounds_node, model),
             radius when is_integer(radius) <- node_int_value(radius_node, model),
             color when is_integer(color) <- node_color_value(color_node, model) do
          {:ok, [x, y, w, h, radius, color]}
        else
          _ -> :error
        end

      {kind, [bounds_node, start_node, end_node | _]} when kind in ["arc", "fillRadial"] ->
        with {:ok, [x, y, w, h]} <- rect_node_ints(bounds_node, model),
             start_angle when is_integer(start_angle) <- node_int_value(start_node, model),
             end_angle when is_integer(end_angle) <- node_int_value(end_node, model) do
          {:ok, [x, y, w, h, start_angle, end_angle]}
        else
          _ -> :error
        end

      {"pixel", [pos_node, color_node | _]} ->
        with {:ok, [x, y]} <- point_node_ints(pos_node, model),
             color when is_integer(color) <- node_color_value(color_node, model) do
          {:ok, [x, y, color]}
        else
          _ -> :error
        end

      {"line", [start_node, end_node, color_node | _]} ->
        with {:ok, [x1, y1]} <- point_node_ints(start_node, model),
             {:ok, [x2, y2]} <- point_node_ints(end_node, model),
             color when is_integer(color) <- node_color_value(color_node, model) do
          {:ok, [x1, y1, x2, y2, color]}
        else
          _ -> :error
        end

      {kind, [center_node, radius_node, color_node | _]} when kind in ["circle", "fillCircle"] ->
        with {:ok, [cx, cy]} <- point_node_ints(center_node, model),
             radius when is_integer(radius) <- node_int_value(radius_node, model),
             color when is_integer(color) <- node_color_value(color_node, model) do
          {:ok, [cx, cy, radius, color]}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  @spec node_int_value(term()) :: term()
  defp node_int_value(node), do: node_int_value(node, %{})

  @spec node_int_value(term(), term()) :: term()
  defp node_int_value(node, model) when is_map(node) do
    evaluated = evaluated_node_value(node, model)
    value = Map.get(node, "value") || Map.get(node, :value)

    cond do
      is_integer(evaluated) ->
        evaluated

      is_float(evaluated) ->
        trunc(evaluated)

      is_integer(value) ->
        value

      is_float(value) ->
        trunc(value)

      is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} -> parsed
          _ -> nil
        end

      true ->
        label = (Map.get(node, "label") || Map.get(node, :label) || "") |> to_string()
        label_ints = extract_ints(label)
        List.first(label_ints)
    end
  end

  defp node_int_value(_node, _model), do: nil

  @spec evaluated_node_value(term(), term()) :: term()
  defp evaluated_node_value(node, model) when is_map(node) and is_map(model) do
    ElmExecutor.Runtime.SemanticExecutor.evaluate_view_tree_value(node, model, %{})
  end

  defp evaluated_node_value(_node, _model), do: nil

  @spec node_color_value(map(), term()) :: integer() | nil
  defp node_color_value(node, model) when is_map(node) do
    node_int_value(node, model) || color_constructor_value(node, model)
  end

  @spec bitmap_node_id(map(), term()) :: integer() | nil
  defp bitmap_node_id(node, model) when is_map(node) do
    evaluated = evaluated_node_value(node, model)

    target =
      to_string(Map.get(node, "qualified_target") || Map.get(node, :qualified_target) || "")

    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "")

    cond do
      is_integer(evaluated) ->
        evaluated

      is_integer(Map.get(node, "tag") || Map.get(node, :tag)) ->
        Map.get(node, "tag") || Map.get(node, :tag)

      target in ["Resources.NoBitmap", "Pebble.Ui.Resources.NoBitmap"] or type == "NoBitmap" ->
        0

      true ->
        nil
    end
  end

  @spec color_constructor_value(map(), term()) :: integer() | nil
  defp color_constructor_value(node, model) when is_map(node) do
    target =
      to_string(Map.get(node, "qualified_target") || Map.get(node, :qualified_target) || "")

    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "")
    name = target |> String.split(".") |> List.last()
    name = if name in [nil, ""], do: type, else: name

    case name do
      "indexed" ->
        node
        |> node_children()
        |> List.first()
        |> node_int_value(model)

      "clearColor" ->
        0x00

      "black" ->
        0xC0

      "red" ->
        0xF0

      "chromeYellow" ->
        0xF8

      "green" ->
        0xCC

      "blue" ->
        0xC3

      "white" ->
        0xFF

      _ ->
        nil
    end
  end

  @spec rect_node_ints(term(), term()) :: {:ok, [integer()]} | :error
  defp rect_node_ints(node, model), do: record_field_ints(node, ["x", "y", "w", "h"], model)

  @spec point_node_ints(term(), term()) :: {:ok, [integer()]} | :error
  defp point_node_ints(node, model), do: record_field_ints(node, ["x", "y"], model)

  @spec record_field_ints(term(), [String.t()], term()) :: {:ok, [integer()]} | :error
  defp record_field_ints(node, keys, model) when is_map(node) and is_list(keys) do
    evaluated = evaluated_node_value(node, model)

    values =
      Enum.map(keys, fn key ->
        field_value =
          cond do
            is_map(evaluated) ->
              Map.get(evaluated, key) || Map.get(evaluated, String.to_atom(key))

            true ->
              nil
          end

        if is_integer(field_value) do
          field_value
        else
          node
          |> field_node(key)
          |> field_value_int(model)
        end
      end)

    if Enum.all?(values, &is_integer/1), do: {:ok, values}, else: :error
  end

  defp record_field_ints(_node, _keys, _model), do: :error

  @spec field_node(term(), String.t()) :: map() | nil
  defp field_node(node, key) when is_map(node) and is_binary(key) do
    node
    |> node_children()
    |> Enum.find(fn child ->
      to_string(Map.get(child, "type") || Map.get(child, :type) || "") == "field" and
        to_string(Map.get(child, "label") || Map.get(child, :label) || "") == key
    end)
  end

  defp field_node(_node, _key), do: nil

  @spec node_children(term()) :: [map()]
  defp node_children(node) when is_map(node) do
    case Map.get(node, "children") || Map.get(node, :children) do
      list when is_list(list) ->
        Enum.filter(list, &is_map/1)

      _ ->
        type = to_string(Map.get(node, "type") || Map.get(node, :type) || "")
        op = to_string(Map.get(node, "op") || Map.get(node, :op) || "")
        fields = Map.get(node, "fields") || Map.get(node, :fields)

        if (type == "record" or (type == "expr" and op == "record_literal")) and is_map(fields) do
          fields
          |> Enum.map(fn {k, v} ->
            child =
              cond do
                is_map(v) -> v
                is_integer(v) -> %{"type" => "expr", "value" => v}
                is_float(v) -> %{"type" => "expr", "value" => trunc(v)}
                is_binary(v) -> %{"type" => "expr", "label" => v}
                true -> %{"type" => "expr", "label" => to_string(v)}
              end

            %{
              "type" => "field",
              "label" => to_string(k),
              "children" => [child]
            }
          end)
        else
          []
        end
    end
  end

  @spec path_from_view_node(term()) :: term()
  defp path_from_view_node(node) when is_map(node) do
    children = node_children(node)

    case children do
      [points_node, ox_node, oy_node, rot_node | _] ->
        with {:ok, points} <- points_from_points_node(points_node),
             ox when is_integer(ox) <- node_int_value(ox_node),
             oy when is_integer(oy) <- node_int_value(oy_node),
             rot when is_integer(rot) <- node_int_value(rot_node) do
          {:ok, %{points: points, offset_x: ox, offset_y: oy, rotation: rot}}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  @spec points_from_points_node(term()) :: term()
  defp points_from_points_node(node) when is_map(node) do
    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "")

    if type == "List" do
      children = node_children(node)

      pairs =
        children
        |> Enum.map(&point_pair_from_point_node/1)

      if Enum.all?(pairs, &match?({:ok, _}, &1)) do
        {:ok, Enum.map(pairs, fn {:ok, pair} -> pair end)}
      else
        :error
      end
    else
      :error
    end
  end

  @spec point_pair_from_point_node(term()) :: term()
  defp point_pair_from_point_node(node) when is_map(node) do
    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "")
    op = to_string(Map.get(node, "op") || Map.get(node, :op) || "")

    case {type, op} do
      {"tuple2", _} ->
        children = node_children(node)

        case children do
          [x_node, y_node | _] ->
            x = node_int_value(x_node)
            y = node_int_value(y_node)
            if is_integer(x) and is_integer(y), do: {:ok, [x, y]}, else: :error

          _ ->
            :error
        end

      {"record", _} ->
        fields =
          node
          |> node_children()
          |> Enum.filter(&(to_string(Map.get(&1, "type") || Map.get(&1, :type) || "") == "field"))

        x =
          fields
          |> Enum.find(&(to_string(Map.get(&1, "label") || Map.get(&1, :label) || "") == "x"))
          |> field_value_int()

        y =
          fields
          |> Enum.find(&(to_string(Map.get(&1, "label") || Map.get(&1, :label) || "") == "y"))
          |> field_value_int()

        if is_integer(x) and is_integer(y), do: {:ok, [x, y]}, else: :error

      {"expr", "record_literal"} ->
        fields =
          node
          |> node_children()
          |> Enum.filter(&(to_string(Map.get(&1, "type") || Map.get(&1, :type) || "") == "field"))

        x =
          fields
          |> Enum.find(&(to_string(Map.get(&1, "label") || Map.get(&1, :label) || "") == "x"))
          |> field_value_int()

        y =
          fields
          |> Enum.find(&(to_string(Map.get(&1, "label") || Map.get(&1, :label) || "") == "y"))
          |> field_value_int()

        if is_integer(x) and is_integer(y), do: {:ok, [x, y]}, else: :error

      _ ->
        :error
    end
  end

  defp point_pair_from_point_node(_), do: :error

  @spec field_value_int(term()) :: integer() | nil
  defp field_value_int(field_node), do: field_value_int(field_node, %{})

  @spec field_value_int(term(), term()) :: integer() | nil
  defp field_value_int(field_node, model) when is_map(field_node) do
    case node_children(field_node) do
      [value_node | _] -> node_int_value(value_node, model)
      _ -> nil
    end
  end

  defp field_value_int(_field_node, _model), do: nil

  @spec extract_ints(term()) :: term()
  defp extract_ints(text) when is_binary(text) do
    Regex.scan(~r/-?\d+/, text)
    |> Enum.map(fn [raw] -> String.to_integer(raw) end)
  end

  @spec require_ints(term(), term()) :: term()
  defp require_ints(values, required)
       when is_list(values) and is_integer(required) and required > 0 do
    if length(values) >= required do
      head = Enum.take(values, required)
      if Enum.all?(head, &is_integer/1), do: {:ok, head}, else: :error
    else
      :error
    end
  end

  defp require_ints(_values, _required), do: :error

  @spec clamp(term(), term(), term()) :: term()
  defp clamp(value, min, max) when is_integer(value), do: max(min, min(value, max))
  defp clamp(_value, min, _max), do: min
end
