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

  @spec normalize(term()) :: map()
  def normalize(term) do
    case coerce(term) do
      %{"type" => _} = node ->
        node

      %{type: type} = node when is_binary(type) or is_atom(type) ->
        stringify_keys(node)

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

  def coerce(list) when is_list(list), do: Enum.map(list, &coerce/1)
  def coerce(other), do: other

  defp coerce_ctor("WindowStack", windows) when is_list(windows),
    do: PebbleUi.window_stack(windows)
  defp coerce_ctor("WindowNode", [id, layers]), do: PebbleUi.window(id, layers)
  defp coerce_ctor("CanvasLayer", [id, ops]), do: PebbleUi.canvas_layer(id, ops)
  defp coerce_ctor("Group", [ctx]), do: PebbleUi.group(coerce_group_context(ctx))

  defp coerce_ctor("Clear", [color]), do: PebbleUi.clear(color)
  defp coerce_ctor("FillRect", [bounds, color]), do: PebbleUi.fill_rect(bounds, color)
  defp coerce_ctor("TextInt", [font, x, y, value]), do: PebbleUi.text_int(font, {x, y}, value)
  defp coerce_ctor("TextLabel", [font, x, y, label]), do: PebbleUi.text_label(font, {x, y}, label)
  defp coerce_ctor("Line", [from, to, color]), do: PebbleUi.line(from, to, color)
  defp coerce_ctor("Rect", [bounds, color]), do: PebbleUi.rect(bounds, color)
  defp coerce_ctor("FillCircle", [center, color]), do: PebbleUi.fill_circle(center, color)
  defp coerce_ctor("FillRadial", [bounds, start_angle, end_angle]),
    do: PebbleUi.fill_radial(bounds, start_angle, end_angle)

  defp coerce_ctor("RoundRect", [bounds, radius, color]),
    do: PebbleUi.round_rect(bounds, radius, color)

  defp coerce_ctor("Arc", [bounds, start, finish]), do: PebbleUi.arc(bounds, start, finish)
  defp coerce_ctor("DrawBitmapInRect", [resource, bounds]), do: PebbleUi.draw_bitmap_in_rect(resource, bounds)
  defp coerce_ctor("Pixel", [pos, color]), do: PebbleUi.pixel(pos, color)
  defp coerce_ctor(_other, _args), do: nil

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
        %{"ctor" => "StrokeColor", "args" => [v]} -> Map.put(acc, "stroke_color", v)
        %{"ctor" => "FillColor", "args" => [v]} -> Map.put(acc, "fill_color", v)
        %{"ctor" => "TextColor", "args" => [v]} -> Map.put(acc, "text_color", v)
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
