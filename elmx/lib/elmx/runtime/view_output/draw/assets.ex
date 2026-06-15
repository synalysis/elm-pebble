defmodule Elmx.Runtime.ViewOutput.Draw.Assets do
  @moduledoc false

  alias Elmx.Types
  alias Elmx.Runtime.ViewOutput.Geometry
  alias Elmx.Runtime.ViewOutput.Resources

  @type opts :: Types.view_output_opts()

  @spec row(map(), opts()) :: Types.view_output_row() | nil
  def row(%{"type" => "drawBitmapInRect"} = node, opts) do
    {x, y, w, h} = Geometry.rect_fields(node, "bounds") |> Geometry.sanitize_rect(node, opts)
    resource = Map.get(node, "resource") || Map.get(node, :resource)
    indices = Resources.bitmap_resource_indices(opts)

    %{
      "kind" => "bitmap_in_rect",
      "resource" => Resources.resource_name(resource),
      "bitmap_id" => Resources.resource_bitmap_id(resource, indices),
      "x" => x,
      "y" => y,
      "w" => w,
      "h" => h
    }
  end

  def row(%{"type" => "drawBitmapSequenceAt"} = node, opts) do
    {x, y} = Geometry.point_xy(node, "origin")
    resource = Map.get(node, "resource") || Map.get(node, :resource)
    indices = Resources.animation_resource_indices(opts)

    %{
      "kind" => "bitmap_sequence_at",
      "resource" => Resources.resource_name(resource),
      "animation_id" => Resources.resource_animation_id(resource, indices),
      "x" => x,
      "y" => y
    }
  end

  def row(%{"type" => "drawRotatedBitmap"} = node, opts) do
    {x, y} = Geometry.point_xy(node, "origin")
    resource = Map.get(node, "resource") || Map.get(node, :resource)
    indices = Resources.bitmap_resource_indices(opts)
    bounds = Map.get(node, "bounds") || Map.get(node, :bounds) || %{}

    %{
      "kind" => "rotated_bitmap",
      "resource" => Resources.resource_name(resource),
      "bitmap_id" => Resources.resource_bitmap_id(resource, indices),
      "center_x" => x,
      "center_y" => y,
      "angle" => Geometry.int_field(node, "rotation", Geometry.int_field(node, "angle", 0)),
      "src_w" => Geometry.int_field(bounds, "w", Geometry.int_field(node, "src_w", 0)),
      "src_h" => Geometry.int_field(bounds, "h", Geometry.int_field(node, "src_h", 0))
    }
  end

  def row(%{"type" => "drawVectorAt"} = node, opts) do
    {x, y} = Geometry.point_xy(node, "origin")
    resource = Map.get(node, "resource") || Map.get(node, :resource)
    indices = Resources.vector_resource_indices(opts)

    %{
      "kind" => "vector_at",
      "resource" => Resources.resource_name(resource),
      "vector_id" => Resources.vector_id(node, resource, indices),
      "x" => x,
      "y" => y
    }
  end

  def row(%{"type" => "drawVectorSequenceAt"} = node, opts) do
    {x, y} = Geometry.point_xy(node, "origin")
    resource = Map.get(node, "resource") || Map.get(node, :resource)
    indices = Resources.vector_resource_indices(opts)

    %{
      "kind" => "vector_sequence_at",
      "resource" => Resources.resource_name(resource),
      "vector_id" => Resources.vector_id(node, resource, indices),
      "x" => x,
      "y" => y
    }
  end

  def row(_node, _opts), do: nil
end
