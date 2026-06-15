defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Rendered.Normalize.Args do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerPreview.SvgTextOptions
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Rendered.Expr
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Rendered.Normalize.Geometry
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types

  @type rendered_node :: Types.rendered_node()
  @type runtime_value :: Types.runtime_value()

  @spec fields(String.t() | atom()) :: [String.t()]
  def fields(type) do
    case to_string(type || "") do
      "clear" -> ["color"]
      "pixel" -> ["x", "y", "color"]
      "line" -> ["x1", "y1", "x2", "y2", "color"]
      "rect" -> ["x", "y", "w", "h", "color"]
      "fillRect" -> ["x", "y", "w", "h", "fill"]
      "circle" -> ["cx", "cy", "r", "color"]
      "fillCircle" -> ["cx", "cy", "r", "color"]
      "roundRect" -> ["x", "y", "w", "h", "radius", "fill"]
      "arc" -> ["x", "y", "w", "h", "start_angle", "end_angle"]
      "fillRadial" -> ["x", "y", "w", "h", "start_angle", "end_angle"]
      "bitmapInRect" -> ["bitmap_id", "x", "y", "w", "h"]
      "rotatedBitmap" -> ["bitmap_id", "src_w", "src_h", "angle", "center_x", "center_y"]
      "drawVectorAt" -> ["vector_id", "x", "y"]
      "drawVectorSequenceAt" -> ["vector_id", "x", "y"]
      "drawBitmapSequenceAt" -> ["animation_id", "x", "y"]
      "textInt" -> ["font_id", "x", "y", "value"]
      "textLabel" -> ["font_id", "x", "y", "text"]
      "text" -> ["font_id", "x", "y", "w", "h", "text_align", "text_overflow", "text"]
      _ -> []
    end
  end

  @spec promote(rendered_node()) :: rendered_node()
  def promote(%{"type" => "window", "children" => [id | rest]} = node) do
    case Expr.expr_scalar(id) do
      nil -> node
      value -> node |> Map.put("id", value) |> Map.put("children", rest)
    end
  end

  def promote(%{"type" => "canvasLayer", "children" => [id | rest]} = node) do
    case Expr.expr_scalar(id) do
      nil -> node
      value -> node |> Map.put("id", value) |> Map.put("children", rest)
    end
  end

  def promote(%{"type" => "text", "children" => children} = node)
      when is_list(children) and length(children) == 6 do
    values = Enum.map(children, &Expr.expr_scalar/1)

    if Enum.all?(values, &(!is_nil(&1))) do
      ["font_id", "x", "y", "w", "h", "text"]
      |> Enum.zip(values)
      |> Enum.reduce(Map.put(node, "children", []), fn {field, value}, acc ->
        put_arg(acc, field, value)
      end)
      |> Map.put("text_align", "center")
      |> Map.put("text_overflow", "word_wrap")
    else
      node
    end
  end

  def promote(%{"type" => "line", "children" => [from, to, color]} = node) do
    with {:ok, {x1, y1}} <- Geometry.point_child(from),
         {:ok, {x2, y2}} <- Geometry.point_child(to),
         stroke when is_integer(stroke) <- Geometry.scalar_color(color) do
      node
      |> Map.put("children", [])
      |> Map.put("x1", x1)
      |> Map.put("y1", y1)
      |> Map.put("x2", x2)
      |> Map.put("y2", y2)
      |> Map.put("color", stroke)
    else
      _ -> node
    end
  end

  def promote(%{"type" => "roundRect", "children" => [bounds, radius, color]} = node) do
    with {:ok, {x, y, w, h}} <- Geometry.rect_child(bounds),
         radius when is_integer(radius) <- Geometry.scalar_int(radius),
         fill when is_integer(fill) <- Geometry.scalar_color(color) do
      node
      |> Map.put("children", [])
      |> Map.put("x", x)
      |> Map.put("y", y)
      |> Map.put("w", w)
      |> Map.put("h", h)
      |> Map.put("radius", radius)
      |> Map.put("fill", fill)
    else
      _ -> node
    end
  end

  def promote(%{"children" => children} = node) when is_list(children) do
    field_list = fields(Map.get(node, "type"))

    if field_list != [] and length(field_list) == length(children) do
      values = Enum.map(children, &Expr.expr_scalar/1)

      if Enum.all?(values, &(!is_nil(&1))) do
        field_list
        |> Enum.zip(values)
        |> Enum.reduce(Map.put(node, "children", []), fn {field, value}, acc ->
          put_arg(acc, field, value)
        end)
      else
        node
      end
    else
      node
    end
  end

  def promote(node), do: node

  @spec text_field(rendered_node()) :: rendered_node()
  def text_field(%{"text" => value} = node) do
    case text(value) do
      nil -> node
      normalized -> Map.put(node, "text", normalized)
    end
  end

  def text_field(node), do: node

  @spec text(runtime_value()) :: String.t() | nil
  def text(value) when is_binary(value) do
    if String.trim(value) != "", do: value, else: nil
  end

  def text(value) when is_integer(value), do: Integer.to_string(value)

  def text(value) when is_float(value),
    do: :erlang.float_to_binary(value, [:compact])

  def text(value) when is_list(value) do
    if List.ascii_printable?(value) do
      value
      |> List.to_string()
      |> text()
    else
      nil
    end
  end

  def text(_value), do: nil

  @spec put_arg(rendered_node(), String.t(), runtime_value()) :: rendered_node()
  defp put_arg(node, "text", value) when is_map(node) do
    Map.put(node, "text", text(value) || "")
  end

  defp put_arg(node, "text_align", value) when is_map(node) do
    Map.put(node, "text_align", SvgTextOptions.normalized_alignment(value))
  end

  defp put_arg(node, "text_overflow", value) when is_map(node) do
    Map.put(node, "text_overflow", SvgTextOptions.normalized_overflow(value))
  end

  defp put_arg(node, field, value) when is_map(node) do
    Map.put(node, field, value)
  end
end
