defmodule Elmx.Runtime.ViewOutput.Draw.Text do
  @moduledoc false

  alias Elmx.Types
  alias Elmx.Runtime.ViewOutput.Geometry

  @type opts :: Types.view_output_opts()

  @spec row(Types.view_draw_node(), opts()) :: Types.view_output_row() | nil
  def row(%{"type" => "text"} = node, _opts) do
    {x, y, w, h} = Geometry.rect_bounds(node, "bounds")

    %{
      "kind" => "text",
      "x" => x,
      "y" => y,
      "w" => w,
      "h" => h,
      "font_id" => Geometry.int_field(node, "font_id", 0),
      "text" => Geometry.text_content(node),
      "text_align" => Geometry.text_align(node),
      "text_overflow" => Geometry.text_overflow(node)
    }
  end

  def row(%{"type" => "textInt"} = node, _opts) do
    {x, y} = Geometry.point_xy(node, "position")

    %{
      "kind" => "text_int",
      "x" => x,
      "y" => y,
      "font_id" => Geometry.int_field(node, "font_id", 0),
      "text" => Geometry.text_content(node)
    }
  end

  def row(%{"type" => "textLabel"} = node, _opts) do
    {x, y} = Geometry.point_xy(node, "position")

    %{
      "kind" => "text_label",
      "x" => x,
      "y" => y,
      "font_id" => Geometry.int_field(node, "font_id", 0),
      "text" => Geometry.label_display_text(node)
    }
  end

  def row(_node, _opts), do: nil
end
