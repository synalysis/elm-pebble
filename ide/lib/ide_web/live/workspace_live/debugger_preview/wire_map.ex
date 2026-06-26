defmodule IdeWeb.WorkspaceLive.DebuggerPreview.WireMap do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerPreview.Geometry
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: PreviewTypes

  @type draw_op_map :: PreviewTypes.draw_op_map()
  @type wire_map :: PreviewTypes.wire_map()
  @type svg_path :: PreviewTypes.svg_path()

  @spec map_integer(draw_op_map(), String.t(), integer() | atom() | nil) ::
          integer() | atom() | nil
  def map_integer(map, key, fallback) when is_map(map) and is_binary(key) do
    atom_key = atom_key_for(key)
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

  @spec map_integer_required(draw_op_map(), String.t()) :: {:ok, integer()} | :error
  def map_integer_required(map, key) when is_map(map) and is_binary(key) do
    value = map_integer(map, key, :__missing__)
    if is_integer(value), do: {:ok, value}, else: :error
  end

  def map_integer_required(_map, _key), do: :error

  @spec map_integers_required(draw_op_map(), [String.t()]) :: {:ok, [integer()]} | :error
  def map_integers_required(map, keys) when is_map(map) and is_list(keys) do
    values = Enum.map(keys, &map_integer_required(map, &1))

    if Enum.all?(values, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(values, fn {:ok, value} -> value end)}
    else
      :error
    end
  end

  def map_integers_required(_map, _keys), do: :error

  @spec map_path_required(draw_op_map()) :: {:ok, svg_path()} | :error
  def map_path_required(map) when is_map(map) do
    with {:ok, points} <- map_points_required(map),
         {:ok, offset_x} <- map_integer_required(map, "offset_x"),
         {:ok, offset_y} <- map_integer_required(map, "offset_y"),
         {:ok, rotation} <- map_integer_required(map, "rotation") do
      {:ok, %{points: points, offset_x: offset_x, offset_y: offset_y, rotation: rotation}}
    else
      _ -> :error
    end
  end

  @spec map_points_required(draw_op_map()) :: {:ok, [[integer()]]} | :error
  def map_points_required(map) when is_map(map) do
    points = Map.get(map, "points") || Map.get(map, :points)

    cond do
      is_list(points) and points != [] ->
        normalized = Enum.map(points, &Geometry.normalize_point_pair/1)

        if Enum.all?(normalized, &match?({:ok, _}, &1)) do
          {:ok, Enum.map(normalized, fn {:ok, pair} -> pair end)}
        else
          :error
        end

      true ->
        :error
    end
  end

  defp atom_key_for(key) when is_binary(key) do
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
      "animation_id" -> :animation_id
      "vector_id" -> :vector_id
      "font_id" -> :font_id
      "src_w" -> :src_w
      "src_h" -> :src_h
      "angle" -> :angle
      "center_x" -> :center_x
      "center_y" -> :center_y
      _ -> nil
    end
  end
end
