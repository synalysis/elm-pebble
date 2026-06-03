defmodule Elmx.Runtime.ViewShape.Geometry do
  @moduledoc false

  alias Elmx.Runtime.Pebble.Ui, as: PebbleUi

  def coerce_path_value(%{"type" => "path"} = path), do: path
  def coerce_path_value(%{type: "path"} = path), do: path

  def coerce_path_value(%{"ctor" => "Path", "args" => [points, origin, rotation]}),
    do: PebbleUi.path(coerce_path_points(points), coerce_point_map(origin), coerce_rotation(rotation))

  def coerce_path_value(%{ctor: :Path, args: [points, origin, rotation]}),
    do: PebbleUi.path(coerce_path_points(points), coerce_point_map(origin), coerce_rotation(rotation))

  def coerce_path_value(path), do: path

  def coerce_path_points(points) when is_list(points) do
    Enum.map(points, &coerce_point_map/1)
  end

  def coerce_path_points(_), do: []

  def coerce_point_map(%{"x" => x, "y" => y}) when is_integer(x) and is_integer(y), do: %{x: x, y: y}
  def coerce_point_map(%{x: x, y: y}) when is_integer(x) and is_integer(y), do: %{x: x, y: y}
  def coerce_point_map({x, y}) when is_integer(x) and is_integer(y), do: %{x: x, y: y}

  def coerce_point_map(%{"ctor" => ctor, "args" => args}) when is_binary(ctor),
    do: coerce_point_map(%{ctor: String.to_atom(ctor), args: args})

  def coerce_point_map(%{ctor: ctor, args: args}) when is_atom(ctor) do
    case {ctor, args} do
      {:Point, [x, y]} when is_integer(x) and is_integer(y) -> %{x: x, y: y}
      {_, [x, y]} when is_integer(x) and is_integer(y) -> %{x: x, y: y}
      _ -> %{x: 0, y: 0}
    end
  end

  def coerce_point_map(_), do: %{x: 0, y: 0}

  def coerce_rotation(value) when is_integer(value), do: value
  def coerce_rotation(_), do: 0

  def rect_map(x, y, w, h), do: %{x: x, y: y, w: w, h: h}

  def coerce_rect_map(%{x: x, y: y, w: w, h: h}) when is_integer(x),
    do: %{x: x, y: y, w: w, h: h}

  def coerce_rect_map(%{"x" => x, "y" => y, "w" => w, "h" => h}) when is_integer(x),
    do: %{x: x, y: y, w: w, h: h}

  def coerce_rect_map(%{ctor: ctor, args: args}) when is_atom(ctor),
    do: coerce_rect_map(%{ctor: Atom.to_string(ctor), args: args})

  def coerce_rect_map(%{"ctor" => "Rect", "args" => [x, y, w, h]}) when is_integer(x),
    do: rect_map(x, y, w, h)

  def coerce_rect_map(%{"ctor" => ctor, "args" => args}) when is_binary(ctor),
    do: coerce_rect_map(%{ctor: ctor, args: args})

  def coerce_rect_map(_), do: %{x: 0, y: 0, w: 0, h: 0}

end
