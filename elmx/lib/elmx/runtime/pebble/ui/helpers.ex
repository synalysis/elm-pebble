defmodule Elmx.Runtime.Pebble.Ui.Helpers do
  @moduledoc false

  alias Elmx.Runtime.Pebble.Colors

  def draw_op(op) when is_map(op), do: op
  def draw_op(other), do: %{type: "drawOp", label: inspect(other)}

  def normalize_child(%{type: _} = node), do: node
  def normalize_child(other), do: %{type: "node", label: inspect(other)}

  def expr_node(value), do: %{type: "expr", label: inspect(value)}

  def color_value(color), do: Colors.to_int(color)

  def point_xy(%{"x" => x, "y" => y}), do: {int_value(x), int_value(y)}
  def point_xy(%{x: x, y: y}), do: {int_value(x), int_value(y)}
  def point_xy({x, y}), do: {int_value(x), int_value(y)}
  def point_xy(_), do: {0, 0}

  def label_display_text(label) do
    case label do
      :WaitingForCompanion -> "Waiting for companion app"
      "WaitingForCompanion" -> "Waiting for companion app"
      atom when is_atom(atom) -> Atom.to_string(atom)
      other -> to_string(other)
    end
  end

  def int_value(value) when is_integer(value), do: value
  def int_value(value) when is_float(value), do: trunc(value)
  def int_value(_), do: 0

  def bounds_xywh(%{"x" => x, "y" => y, "w" => w, "h" => h}),
    do: {int_value(x), int_value(y), int_value(w), int_value(h)}

  def bounds_xywh(%{x: x, y: y, w: w, h: h}),
    do: {int_value(x), int_value(y), int_value(w), int_value(h)}

  def bounds_xywh({x, y, w, h}) when is_integer(x),
    do: {int_value(x), int_value(y), int_value(w), int_value(h)}

  def bounds_xywh([x, y, w, h]) when is_integer(x),
    do: {int_value(x), int_value(y), int_value(w), int_value(h)}

  def bounds_xywh(_), do: {0, 0, 0, 0}

  def context_style(settings) when is_list(settings) do
    Enum.reduce(settings, %{}, fn
      %{type: "contextSetting", key: key, value: value}, acc ->
        Map.put(acc, context_style_key(key), color_value(value))

      %{"type" => "contextSetting", "key" => key, "value" => value}, acc ->
        Map.put(acc, context_style_key(key), color_value(value))

      %{key: key, value: value}, acc when is_binary(key) ->
        Map.put(acc, context_style_key(key), color_value(value))

      %{"key" => key, "value" => value}, acc when is_binary(key) ->
        Map.put(acc, context_style_key(key), color_value(value))

      other, acc ->
        Map.put(acc, "setting", other)
    end)
  end

  def context_style_key("strokeWidth"), do: "stroke_color"
  def context_style_key("strokeColor"), do: "stroke_color"
  def context_style_key("fillColor"), do: "fill_color"
  def context_style_key("textColor"), do: "text_color"
  def context_style_key("stroke_width"), do: "stroke_color"
  def context_style_key("fill_color"), do: "fill_color"
  def context_style_key("text_color"), do: "text_color"
  def context_style_key("antialiased"), do: "antialiased"
  def context_style_key("compositingMode"), do: "compositing_mode"
  def context_style_key(key) when is_binary(key), do: key
end
