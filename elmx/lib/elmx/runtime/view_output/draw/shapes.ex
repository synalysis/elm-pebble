defmodule Elmx.Runtime.ViewOutput.Draw.Shapes do
  @moduledoc false

  alias Elmx.Types
  alias Elmx.Runtime.ViewOutput.Geometry

  @type opts :: Types.view_output_opts()

  @spec row(Types.view_draw_node(), opts()) :: Types.view_output_row() | nil
  def row(%{"type" => "clear"} = node, _opts),
    do: %{"kind" => "clear", "color" => Geometry.int_field(node, "color", 0xC0)}

  def row(%{"type" => "fillRect"} = node, opts) do
    {x, y, w, h} = Geometry.rect_fields(node, "bounds") |> Geometry.sanitize_rect(node, opts)

    %{
      "kind" => "fill_rect",
      "x" => x,
      "y" => y,
      "w" => w,
      "h" => h,
      "fill" => Geometry.int_field(node, "color", 0)
    }
  end

  def row(%{"type" => "rect"} = node, _opts) do
    {x, y, w, h} = Geometry.rect_fields(node, "bounds")

    %{
      "kind" => "rect",
      "x" => x,
      "y" => y,
      "w" => w,
      "h" => h,
      "fill" => Geometry.int_field(node, "color", 0)
    }
  end

  def row(%{"type" => "roundRect"} = node, _opts) do
    {x, y, w, h} = Geometry.rect_bounds(node, "bounds")

    %{
      "kind" => "round_rect",
      "x" => x,
      "y" => y,
      "w" => w,
      "h" => h,
      "radius" => Geometry.int_field(node, "radius", 0),
      "fill" => Geometry.int_field(node, "fill", Geometry.int_field(node, "color", 0))
    }
  end

  def row(%{"type" => "line"} = node, _opts) do
    {x1, y1, x2, y2} = Geometry.line_endpoints(node)

    %{
      "kind" => "line",
      "x1" => x1,
      "y1" => y1,
      "x2" => x2,
      "y2" => y2,
      "color" => Geometry.int_field(node, "color", 0)
    }
  end

  def row(%{"type" => "circle"} = node, _opts) do
    {cx, cy} = Geometry.point_fields(node, "center")
    {cx, cy} = Geometry.point_fields(node, "position", {cx, cy})

    %{
      "kind" => "circle",
      "cx" => Geometry.int_field(node, "cx", cx),
      "cy" => Geometry.int_field(node, "cy", cy),
      "r" => Geometry.int_field(node, "radius", Geometry.int_field(node, "r", 0)),
      "color" => Geometry.int_field(node, "color", 0)
    }
  end

  def row(%{"type" => "fillCircle"} = node, _opts) do
    {cx, cy} = Geometry.point_fields(node, "center")
    {cx, cy} = Geometry.point_fields(node, "position", {cx, cy})

    %{
      "kind" => "fill_circle",
      "cx" => Geometry.int_field(node, "cx", cx),
      "cy" => Geometry.int_field(node, "cy", cy),
      "r" => Geometry.int_field(node, "radius", Geometry.int_field(node, "r", 0)),
      "color" => Geometry.int_field(node, "color", 0)
    }
  end

  def row(%{"type" => "pixel"} = node, _opts) do
    {x, y} = Geometry.point_xy(node, "position")

    %{
      "kind" => "pixel",
      "x" => x,
      "y" => y,
      "color" => Geometry.int_field(node, "color", 0)
    }
  end

  def row(%{"type" => "arc"} = node, _opts) do
    {x, y, w, h} = Geometry.rect_fields(node, "bounds")

    %{
      "kind" => "arc",
      "x" => x,
      "y" => y,
      "w" => w,
      "h" => h,
      "start_angle" => Geometry.int_field(node, "start_angle", 0),
      "end_angle" => Geometry.int_field(node, "end_angle", 0)
    }
  end

  def row(%{"type" => "fillRadial"} = node, _opts) do
    {x, y, w, h} = Geometry.rect_fields(node, "bounds")

    %{
      "kind" => "fill_radial",
      "x" => x,
      "y" => y,
      "w" => w,
      "h" => h,
      "start_angle" => Geometry.int_field(node, "start_angle", 0),
      "end_angle" => Geometry.int_field(node, "end_angle", 0)
    }
  end

  def row(_node, _opts), do: nil
end
