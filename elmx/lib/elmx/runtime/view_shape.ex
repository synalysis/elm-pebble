defmodule Elmx.Runtime.ViewShape do
  @moduledoc """
  Coerces Elm ADT view values (ctor maps / tagged tuples) into debugger preview maps.

  Used for functions compiled from Elm source (including `Pebble.Ui.*` helpers and
  user-defined wrappers) without name-specific codegen hooks.
  """

  alias Elmx.Runtime.Pebble.Ui, as: PebbleUi

  # Tags assigned in `ElmEx.IR.Lowerer` for virtual `Pebble.Ui` node ADTs.
  @pebble_ui_node_tags %{
    1000 => "WindowStack",
    1001 => "WindowNode",
    1002 => "CanvasLayer"
  }

  @render_op_types MapSet.new(~w(
    clear fillRect rect roundRect line circle fillCircle pixel
    drawVectorAt drawVectorSequenceAt drawBitmapInRect drawBitmapSequenceAt
    drawRotatedBitmap arc fillRadial text textLabel textInt
    path pathFilled pathOutline pathOutlineOpen group
  ))

  @spec normalize(term()) :: map()
  def normalize(term) do
    case coerce(term) do
      %{"type" => _} = node ->
        node

      %{type: type} = node when is_binary(type) or is_atom(type) ->
        stringify_keys(node)

      ops when is_list(ops) ->
        case normalize_render_op_list(ops) do
          {:ok, tree} -> tree
          :error -> %{"type" => "node", "label" => inspect(ops), "children" => []}
        end

      other ->
        %{"type" => "node", "label" => inspect(other), "children" => []}
    end
  end

  @spec coerce(term()) :: term()
  def coerce(%{"type" => _} = node), do: stringify_keys(node)
  def coerce(%{type: _} = node), do: stringify_keys(node)

  def coerce(%{"ctor" => ctor, "args" => args}) when is_binary(ctor) and is_list(args),
    do: coerce_ctor(ctor, Enum.map(args, &coerce/1))

  def coerce({ctor, args}) when is_atom(ctor) and is_list(args),
    do: coerce_ctor(Atom.to_string(ctor), Enum.map(args, &coerce/1))

  def coerce({tag, payload}) when is_integer(tag) do
    case Map.get(@pebble_ui_node_tags, tag) do
      nil ->
        nil

      "WindowStack" ->
        coerce_ctor("WindowStack", tagged_ctor_args(payload))

      ctor ->
        coerce_ctor(ctor, tagged_ctor_args(payload))
    end
  end

  def coerce(tuple) when is_tuple(tuple) do
    case Tuple.to_list(tuple) do
      [ctor | args] when is_atom(ctor) ->
        coerce_ctor(Atom.to_string(ctor), Enum.map(args, &coerce/1))

      _ ->
        tuple
    end
  end

  def coerce(list) when is_list(list), do: Enum.map(list, &coerce/1)
  def coerce(other), do: other

  defp coerce_ctor("WindowStack", windows) when is_list(windows),
    do: PebbleUi.window_stack(windows)
  defp coerce_ctor("WindowNode", [id, layers]), do: PebbleUi.window(id, layers)
  defp coerce_ctor("CanvasLayer", [id, ops]), do: PebbleUi.canvas_layer(id, ops)
  defp coerce_ctor("Group", [ctx]), do: PebbleUi.group(coerce_group_context(ctx))

  defp coerce_ctor("Context", [settings, commands])
       when is_list(settings) and is_list(commands) do
    PebbleUi.context(
      Enum.map(settings, &coerce/1),
      Enum.map(commands, &coerce/1)
    )
  end

  defp coerce_ctor("StrokeWidth", [v]), do: PebbleUi.context_setting("strokeWidth", v)
  defp coerce_ctor("StrokeColor", [v]), do: PebbleUi.context_setting("strokeColor", v)
  defp coerce_ctor("FillColor", [v]), do: PebbleUi.context_setting("fillColor", v)
  defp coerce_ctor("TextColor", [v]), do: PebbleUi.context_setting("textColor", v)
  defp coerce_ctor("Antialiased", [v]), do: PebbleUi.context_setting("antialiased", v)
  defp coerce_ctor("CompositingMode", [v]), do: PebbleUi.context_setting("compositingMode", v)

  defp coerce_ctor("Clear", [color]), do: PebbleUi.clear(color)
  defp coerce_ctor("FillRect", [bounds, color]), do: PebbleUi.fill_rect(bounds, color)
  defp coerce_ctor("FillRect", [x, y, w, h, color]) when is_integer(x),
    do: PebbleUi.fill_rect(rect_map(x, y, w, h), color)

  defp coerce_ctor("TextInt", [font, x, y, value]), do: PebbleUi.text_int(font, {x, y}, value)
  defp coerce_ctor("TextLabel", [font, x, y, label]), do: PebbleUi.text_label(font, {x, y}, label)
  defp coerce_ctor("Circle", [center, radius, color]), do: PebbleUi.circle(center, radius, color)
  defp coerce_ctor("Circle", [center, radius]), do: PebbleUi.circle(center, radius)
  defp coerce_ctor("Circle", [cx, cy, r, color]) when is_integer(cx),
    do: PebbleUi.circle(%{x: cx, y: cy}, r, color)

  defp coerce_ctor("Line", [from, to, color]), do: PebbleUi.line(from, to, color)
  defp coerce_ctor("Line", [x1, y1, x2, y2, color]) when is_integer(x1),
    do: PebbleUi.line(%{x: x1, y: y1}, %{x: x2, y: y2}, color)

  defp coerce_ctor("RectOp", [bounds, color]), do: PebbleUi.rect(bounds, color)
  defp coerce_ctor("RectOp", [x, y, w, h, color]) when is_integer(x),
    do: PebbleUi.rect(rect_map(x, y, w, h), color)

  defp coerce_ctor("Rect", [bounds, color]), do: PebbleUi.rect(bounds, color)
  defp coerce_ctor("FillCircle", [center, radius, color]),
    do: PebbleUi.fill_circle(center, radius, color)

  defp coerce_ctor("FillCircle", [center, color]), do: PebbleUi.fill_circle(center, 0, color)
  defp coerce_ctor("FillCircle", [cx, cy, r, color]) when is_integer(cx),
    do: PebbleUi.fill_circle(%{x: cx, y: cy}, r, color)

  defp coerce_ctor("FillRadial", [bounds, start_angle, end_angle]),
    do: PebbleUi.fill_radial(bounds, start_angle, end_angle)

  defp coerce_ctor("FillRadial", [x, y, w, h, start_angle, end_angle]) when is_integer(x),
    do: PebbleUi.fill_radial(rect_map(x, y, w, h), start_angle, end_angle)

  defp coerce_ctor("RoundRect", [bounds, radius, color]),
    do: PebbleUi.round_rect(bounds, radius, color)

  defp coerce_ctor("RoundRect", [x, y, w, h, radius, color]) when is_integer(x),
    do: PebbleUi.round_rect(rect_map(x, y, w, h), radius, color)

  defp coerce_ctor("Arc", [bounds, start, finish]), do: PebbleUi.arc(bounds, start, finish)
  defp coerce_ctor("Arc", [x, y, w, h, start, finish]) when is_integer(x),
    do: PebbleUi.arc(rect_map(x, y, w, h), start, finish)

  defp coerce_ctor("DrawBitmapInRect", [resource, bounds]), do: PebbleUi.draw_bitmap_in_rect(resource, bounds)

  defp coerce_ctor("BitmapInRect", [resource, x, y, w, h]) when is_integer(x),
    do: PebbleUi.draw_bitmap_in_rect(resource, rect_map(x, y, w, h))

  defp coerce_ctor("DrawBitmapSequenceAt", [resource, origin]),
    do: PebbleUi.draw_bitmap_sequence_at(resource, coerce_point_map(origin))

  defp coerce_ctor("BitmapSequenceAt", [resource, x, y]) when is_integer(x),
    do: PebbleUi.draw_bitmap_sequence_at(resource, %{x: x, y: y})

  defp coerce_ctor("DrawRotatedBitmap", [resource, bounds, rotation, center]),
    do: PebbleUi.draw_rotated_bitmap(resource, coerce_rect_map(bounds), rotation, coerce_point_map(center))

  defp coerce_ctor("RotatedBitmap", [resource, src_w, src_h, angle, center_x, center_y])
       when is_integer(src_w),
       do:
         PebbleUi.draw_rotated_bitmap(
           resource,
           %{x: 0, y: 0, w: src_w, h: src_h},
           angle,
           %{x: center_x, y: center_y}
         )

  defp coerce_ctor("Pixel", [pos, color]), do: PebbleUi.pixel(pos, color)
  defp coerce_ctor("Pixel", [x, y, color]) when is_integer(x), do: PebbleUi.pixel(%{x: x, y: y}, color)
  defp coerce_ctor("DrawVectorAt", [resource, frame, origin, rotation]),
    do: PebbleUi.draw_vector_at(resource, frame, origin, rotation)

  defp coerce_ctor("DrawVectorAt", [resource, origin]),
    do: PebbleUi.draw_vector_at(resource, origin)

  defp coerce_ctor("DrawVectorSequenceAt", [resource, frame, origin, rotation]),
    do: PebbleUi.draw_vector_sequence_at(resource, frame, origin, rotation)

  defp coerce_ctor("DrawVectorSequenceAt", [resource, origin]),
    do: PebbleUi.draw_vector_sequence_at(resource, origin)

  defp coerce_ctor("Text", [font, options, bounds, value]),
    do: PebbleUi.text(font, options, bounds, value)

  defp coerce_ctor("Path", [points, origin, rotation]),
    do: PebbleUi.path(coerce_path_points(points), coerce_point_map(origin), coerce_rotation(rotation))

  defp coerce_ctor("PathFilled", [path]), do: PebbleUi.path_filled(coerce_path_value(path))
  defp coerce_ctor("PathOutline", [path]), do: PebbleUi.path_outline(coerce_path_value(path))
  defp coerce_ctor("PathOutlineOpen", [path]), do: PebbleUi.path_outline_open(coerce_path_value(path))

  defp coerce_ctor(_other, _args), do: nil

  defp coerce_path_value(%{"type" => "path"} = path), do: path
  defp coerce_path_value(%{type: "path"} = path), do: path

  defp coerce_path_value(%{"ctor" => "Path", "args" => [points, origin, rotation]}),
    do: PebbleUi.path(coerce_path_points(points), coerce_point_map(origin), coerce_rotation(rotation))

  defp coerce_path_value(%{ctor: :Path, args: [points, origin, rotation]}),
    do: PebbleUi.path(coerce_path_points(points), coerce_point_map(origin), coerce_rotation(rotation))

  defp coerce_path_value(path), do: path

  defp coerce_path_points(points) when is_list(points) do
    Enum.map(points, &coerce_point_map/1)
  end

  defp coerce_path_points(_), do: []

  defp coerce_point_map(%{"x" => x, "y" => y}) when is_integer(x) and is_integer(y), do: %{x: x, y: y}
  defp coerce_point_map(%{x: x, y: y}) when is_integer(x) and is_integer(y), do: %{x: x, y: y}
  defp coerce_point_map({x, y}) when is_integer(x) and is_integer(y), do: %{x: x, y: y}

  defp coerce_point_map(%{"ctor" => ctor, "args" => args}) when is_binary(ctor),
    do: coerce_point_map(%{ctor: String.to_atom(ctor), args: args})

  defp coerce_point_map(%{ctor: ctor, args: args}) when is_atom(ctor) do
    case {ctor, args} do
      {:Point, [x, y]} when is_integer(x) and is_integer(y) -> %{x: x, y: y}
      {_, [x, y]} when is_integer(x) and is_integer(y) -> %{x: x, y: y}
      _ -> %{x: 0, y: 0}
    end
  end

  defp coerce_point_map(_), do: %{x: 0, y: 0}

  defp coerce_rotation(value) when is_integer(value), do: value
  defp coerce_rotation(_), do: 0

  defp rect_map(x, y, w, h), do: %{x: x, y: y, w: w, h: h}

  defp coerce_rect_map(%{x: x, y: y, w: w, h: h}) when is_integer(x),
    do: %{x: x, y: y, w: w, h: h}

  defp coerce_rect_map(%{"x" => x, "y" => y, "w" => w, "h" => h}) when is_integer(x),
    do: %{x: x, y: y, w: w, h: h}

  defp coerce_rect_map(%{ctor: ctor, args: args}) when is_atom(ctor),
    do: coerce_rect_map(%{ctor: Atom.to_string(ctor), args: args})

  defp coerce_rect_map(%{"ctor" => "Rect", "args" => [x, y, w, h]}) when is_integer(x),
    do: rect_map(x, y, w, h)

  defp coerce_rect_map(%{"ctor" => ctor, "args" => args}) when is_binary(ctor),
    do: coerce_rect_map(%{ctor: ctor, args: args})

  defp coerce_rect_map(_), do: %{x: 0, y: 0, w: 0, h: 0}

  @spec normalize_render_op_list(list()) :: {:ok, map()} | :error
  defp normalize_render_op_list(ops) when is_list(ops) do
    ops =
      Enum.map(ops, fn
        %{"type" => _} = op -> stringify_keys(op)
        %{type: _} = op -> stringify_keys(op)
        other -> coerce(other)
      end)

    if render_op_list?(ops) do
      tree =
        PebbleUi.window_stack([
          PebbleUi.window(1, [
            PebbleUi.canvas_layer(1, ops)
          ])
        ])

      {:ok, stringify_keys(tree)}
    else
      :error
    end
  end

  defp render_op_list?(ops) when is_list(ops),
    do: Enum.all?(ops, &render_op_shape?/1)

  defp render_op_shape?(%{"type" => type}) when is_binary(type), do: draw_op_type?(type)
  defp render_op_shape?(%{type: type}) when is_binary(type) or is_atom(type), do: draw_op_type?(to_string(type))
  defp render_op_shape?(_), do: false

  defp draw_op_type?(type) when is_binary(type), do: MapSet.member?(@render_op_types, type)

  defp tagged_ctor_args({left, right}), do: [coerce(left), coerce(right)]
  defp tagged_ctor_args(list) when is_list(list), do: Enum.map(list, &coerce/1)
  defp tagged_ctor_args(other), do: [coerce(other)]

  defp coerce_group_context({settings, commands}) when is_list(settings) and is_list(commands) do
    %{style: coerce_context_settings(settings), ops: commands}
  end

  defp coerce_group_context(%{"ctor" => "Context", "args" => [{settings, commands}]}) do
    coerce_group_context({settings, commands})
  end

  defp coerce_group_context(%{settings: settings, ops: ops}) when is_list(ops) do
    %{style: coerce_context_settings(settings), ops: ops}
  end

  defp coerce_group_context(other), do: other

  defp coerce_context_settings(settings) when is_list(settings) do
    Enum.reduce(settings, %{}, fn setting, acc ->
      case setting do
        %{"ctor" => "StrokeWidth", "args" => [v]} -> Map.put(acc, "stroke_width", v)
        %{"ctor" => "Antialiased", "args" => [v]} -> Map.put(acc, "antialiased", v)
        %{"ctor" => "StrokeColor", "args" => [v]} ->
          Map.put(acc, "stroke_color", Elmx.Runtime.Pebble.Colors.to_int(v))

        %{"ctor" => "FillColor", "args" => [v]} ->
          Map.put(acc, "fill_color", Elmx.Runtime.Pebble.Colors.to_int(v))

        %{"ctor" => "TextColor", "args" => [v]} ->
          Map.put(acc, "text_color", Elmx.Runtime.Pebble.Colors.to_int(v))
        %{"ctor" => "CompositingMode", "args" => [v]} -> Map.put(acc, "compositing_mode", v)
        {ctor, [v]} when is_atom(ctor) -> Map.put(acc, context_key(ctor), v)
        _ -> acc
      end
    end)
  end

  defp coerce_context_settings(other), do: other

  defp context_key(:StrokeWidth), do: "stroke_width"
  defp context_key(:Antialiased), do: "antialiased"
  defp context_key(:StrokeColor), do: "stroke_color"
  defp context_key(:FillColor), do: "fill_color"
  defp context_key(:TextColor), do: "text_color"
  defp context_key(:CompositingMode), do: "compositing_mode"
  defp context_key(other), do: to_string(other)

  defp stringify_keys(map) when is_map(map) do
    map
    |> Enum.map(fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_keys(v)}
      {k, v} -> {to_string(k), stringify_keys(v)}
    end)
    |> Map.new()
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(other), do: other
end
