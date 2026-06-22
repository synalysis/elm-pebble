defmodule Elmx.Runtime.Pebble.Ui.Assets do
  @moduledoc false

  alias Elmx.Types

  @spec draw_bitmap_in_rect(Types.ui_resource(), Types.ui_bounds()) :: Types.ui_node()
  def draw_bitmap_in_rect(resource, bounds) when is_map(bounds) do
    %{
      type: "drawBitmapInRect",
      label: "drawBitmapInRect",
      resource: resource,
      bounds: bounds
    }
  end

  def draw_bitmap_in_rect(resource, bounds),
    do: %{
      type: "drawBitmapInRect",
      label: "drawBitmapInRect",
      resource: inspect(resource),
      bounds: bounds
    }

  @spec draw_vector_at(
          Types.ui_resource(),
          Types.ui_coord(),
          Types.ui_point(),
          Types.ui_coord()
        ) :: Types.ui_node()
  def draw_vector_at(resource, frame, origin, rotation),
    do: %{
      type: "drawVectorAt",
      label: "drawVectorAt",
      resource: resource,
      frame: frame,
      origin: origin,
      rotation: rotation
    }

  def draw_vector_at(resource, origin),
    do: draw_vector_at(resource, 0, origin, 0)

  @spec draw_vector_sequence_at(
          Types.ui_coord(),
          Types.ui_resource(),
          Types.ui_coord(),
          Types.ui_point(),
          Types.ui_coord()
        ) :: Types.ui_node()
  def draw_vector_sequence_at(animation_id, resource, frame, origin, rotation),
    do: %{
      type: "drawVectorSequenceAt",
      label: "drawVectorSequenceAt",
      animation_id: coerce_animation_id(animation_id),
      resource: resource,
      frame: frame,
      origin: origin,
      rotation: rotation
    }

  def draw_vector_sequence_at(animation_id, resource, origin),
    do: draw_vector_sequence_at(animation_id, resource, 0, origin, 0)

  defp coerce_animation_id(%{"ctor" => "AnimationId", "args" => [value]}), do: value
  defp coerce_animation_id(%{ctor: "AnimationId", args: [value]}), do: value
  defp coerce_animation_id(value) when is_integer(value), do: value
  defp coerce_animation_id(value), do: value

  @spec draw_bitmap_sequence_at(
          Types.ui_coord(),
          Types.ui_resource(),
          Types.ui_coord(),
          Types.ui_point(),
          Types.ui_coord()
        ) :: Types.ui_node()
  def draw_bitmap_sequence_at(animation_id, resource, frame, origin, rotation),
    do: %{
      type: "drawBitmapSequenceAt",
      label: "drawBitmapSequenceAt",
      animation_id: coerce_animation_id(animation_id),
      resource: resource,
      frame: frame,
      origin: origin,
      rotation: rotation
    }

  def draw_bitmap_sequence_at(animation_id, resource, origin),
    do: draw_bitmap_sequence_at(animation_id, resource, 0, origin, 0)

  @spec draw_rotated_bitmap(
          Types.ui_resource(),
          Types.ui_bounds(),
          number(),
          Types.ui_point()
        ) :: Types.ui_node()
  def draw_rotated_bitmap(resource, bounds, rotation, center) when is_map(bounds) do
    %{
      type: "drawRotatedBitmap",
      label: "drawRotatedBitmap",
      resource: resource,
      bounds: bounds,
      rotation: rotation,
      origin: center
    }
  end

  def draw_rotated_bitmap(resource, origin, rotation),
    do: draw_rotated_bitmap(resource, %{x: 0, y: 0, w: 0, h: 0}, rotation, origin)
end
