defmodule Elmx.Runtime.Pebble.Ui do
  @moduledoc false

  alias Elmx.Runtime.Pebble.Ui.{Assets, Primitives, Structure}
  alias Elmx.Types

  @spec window_stack(Types.registry_args()) :: Types.ui_node()
  defdelegate window_stack(windows), to: Structure

  @spec window(Types.ui_layer_id(), Types.registry_args()) :: Types.ui_node()
  defdelegate window(id, layers), to: Structure

  @spec canvas_layer(Types.ui_layer_id(), [Types.ui_node() | map()]) :: Types.ui_node()
  defdelegate canvas_layer(z, ops), to: Structure

  @spec group(Types.wire_map() | map()) :: Types.ui_node()
  def group(arg), do: Structure.group(arg)

  @spec context(Types.registry_args(), Types.registry_args()) :: Types.ui_node()
  defdelegate context(settings, ops), to: Structure

  @spec to_ui_node(Types.view_shape_input()) :: Types.ui_node()
  defdelegate to_ui_node(arg), to: Structure

  @spec draw_bitmap_in_rect(Types.ui_resource(), Types.ui_bounds()) :: Types.ui_node()
  def draw_bitmap_in_rect(resource, bounds), do: Assets.draw_bitmap_in_rect(resource, bounds)

  @spec clear(Types.ui_color()) :: Types.ui_node()
  def clear(color \\ :black), do: Primitives.clear(color)

  @spec named_color(String.t()) :: integer()
  defdelegate named_color(name), to: Primitives

  @spec fill_rect(Types.ui_bounds(), Types.ui_color()) :: Types.ui_node()
  defdelegate fill_rect(bounds, color), to: Primitives

  @spec text(
          Types.ui_font(),
          Types.ui_text_options(),
          Types.ui_bounds(),
          String.t() | Types.ui_coord() | Types.ui_label()
        ) :: Types.ui_node()
  defdelegate text(font, options, bounds, value), to: Primitives

  @spec text_int(Types.ui_font(), Types.ui_point(), Types.ui_coord()) :: Types.ui_node()
  defdelegate text_int(font, pos, value), to: Primitives

  @spec text_label(Types.ui_font(), Types.ui_point(), Types.ui_label()) :: Types.ui_node()
  defdelegate text_label(font, pos, label), to: Primitives

  @spec rect(Types.ui_bounds(), Types.ui_color()) :: Types.ui_node()
  defdelegate rect(bounds, color), to: Primitives

  @spec line(Types.ui_point(), Types.ui_point(), Types.ui_color()) :: Types.ui_node()
  def line(from, to, color \\ :black), do: Primitives.line(from, to, color)

  @spec circle(Types.ui_point(), Types.ui_coord(), Types.ui_color()) :: Types.ui_node()
  def circle(center, radius, color),
    do: Primitives.circle(center, radius, color)

  def circle(center, radius),
    do: Primitives.circle(center, radius)

  @spec fill_circle(Types.ui_point(), Types.ui_coord(), Types.ui_color()) :: Types.ui_node()
  def fill_circle(center, radius, color),
    do: Primitives.fill_circle(center, radius, color)

  def fill_circle(center, color),
    do: Primitives.fill_circle(center, color)

  @spec fill_radial(Types.ui_point(), Types.ui_coord(), Types.ui_color()) :: Types.ui_node()
  defdelegate fill_radial(bounds, start_angle, end_angle), to: Primitives

  @spec pixel(Types.ui_point(), Types.ui_color()) :: Types.ui_node()
  defdelegate pixel(pos, color), to: Primitives

  @spec context_setting(String.t(), Types.ui_color()) :: Types.ui_node()
  defdelegate context_setting(key, value), to: Primitives

  @spec round_rect(Types.ui_bounds(), Types.ui_coord(), Types.ui_color()) :: Types.ui_node()
  defdelegate round_rect(bounds, radius, color), to: Primitives

  @spec arc(Types.ui_point(), Types.ui_coord(), Types.ui_color()) :: Types.ui_node()
  defdelegate arc(bounds, start_angle, end_angle), to: Primitives

  @spec path([Types.ui_point()], Types.ui_point(), Types.ui_coord()) :: Types.ui_node()
  defdelegate path(points, origin, rotation), to: Primitives

  @spec path_outline(Types.ui_path()) :: Types.ui_node()
  defdelegate path_outline(path), to: Primitives

  @spec path_filled(Types.ui_path()) :: Types.ui_node()
  defdelegate path_filled(path), to: Primitives

  @spec path_outline_open(Types.ui_path()) :: Types.ui_node()
  defdelegate path_outline_open(path), to: Primitives

  @spec draw_vector_at(
          Types.ui_resource(),
          Types.ui_coord(),
          Types.ui_point(),
          Types.ui_coord()
        ) :: Types.ui_node()
  def draw_vector_at(resource, frame, origin, rotation),
    do: Assets.draw_vector_at(resource, frame, origin, rotation)

  def draw_vector_at(resource, origin),
    do: Assets.draw_vector_at(resource, origin)

  @spec draw_vector_sequence_at(
          Types.ui_coord(),
          Types.ui_resource(),
          Types.ui_coord(),
          Types.ui_point(),
          Types.ui_coord()
        ) :: Types.ui_node()
  def draw_vector_sequence_at(animation_id, resource, frame, origin, rotation),
    do: Assets.draw_vector_sequence_at(animation_id, resource, frame, origin, rotation)

  def draw_vector_sequence_at(animation_id, resource, origin),
    do: Assets.draw_vector_sequence_at(animation_id, resource, origin)

  @spec draw_bitmap_sequence_at(
          Types.ui_resource(),
          Types.ui_coord(),
          Types.ui_point(),
          Types.ui_coord()
        ) :: Types.ui_node()
  def draw_bitmap_sequence_at(resource, frame, origin, rotation),
    do: Assets.draw_bitmap_sequence_at(resource, frame, origin, rotation)

  def draw_bitmap_sequence_at(resource, origin),
    do: Assets.draw_bitmap_sequence_at(resource, origin)

  @spec draw_rotated_bitmap(
          Types.ui_resource(),
          Types.ui_bounds(),
          number(),
          Types.ui_point()
        ) :: Types.ui_node()
  def draw_rotated_bitmap(resource, bounds, rotation, center),
    do: Assets.draw_rotated_bitmap(resource, bounds, rotation, center)

  def draw_rotated_bitmap(resource, origin, rotation),
    do: Assets.draw_rotated_bitmap(resource, origin, rotation)

  @spec compositing_mode(Types.ui_compositing_mode()) :: Types.ui_node()
  defdelegate compositing_mode(mode), to: Primitives

  @spec rotation_from_degrees(Types.ui_coord()) :: number()
  defdelegate rotation_from_degrees(degrees), to: Primitives
end
