defmodule Elmx.Runtime.ViewOutput.Tree do
  @moduledoc false

  alias Elmx.Types
  alias Elmx.Runtime.ViewOutput.Draw

  @draw_types ~w(
    clear fillRect rect roundRect line circle fillCircle pixel
    drawVectorAt drawVectorSequenceAt drawBitmapInRect drawBitmapSequenceAt
    drawRotatedBitmap arc fillRadial text textLabel textInt
    path pathFilled pathOutline pathOutlineOpen
  )

  @type opts :: Types.view_output_opts()

  @spec flatten_node(Types.view_shape_input(), opts()) :: [Types.view_output_row()]
  def flatten_node(%{type: type} = node, opts) when is_binary(type) or is_atom(type) do
    type = to_string(type)

    cond do
      type in ["windowStack", "WindowStack"] ->
        children(node) |> Enum.flat_map(&flatten_node(&1, opts))

      type in ["window", "Window", "WindowNode"] ->
        children(node) |> Enum.flat_map(&flatten_node(&1, opts))

      type in ["canvasLayer", "CanvasLayer"] ->
        children(node)
        |> Enum.reject(&expr_placeholder?/1)
        |> Enum.flat_map(&flatten_node(&1, opts))

      type == "group" ->
        style_rows(node) ++ (children(node) |> Enum.flat_map(&flatten_node(&1, opts)))

      type in @draw_types ->
        case Draw.draw_row(node, opts) do
          nil -> []
          row -> [row]
        end

      true ->
        children(node) |> Enum.flat_map(&flatten_node(&1, opts))
    end
  end

  def flatten_node(%{"type" => type} = node, opts) when is_binary(type),
    do: flatten_node(Map.put_new(node, :type, type), opts)

  def flatten_node(_node, _opts), do: []

  def expr_placeholder?(%{"type" => "expr"}), do: true
  def expr_placeholder?(%{type: "expr"}), do: true
  def expr_placeholder?(_), do: false

  def children(node) when is_map(node) do
    case Map.get(node, "children") || Map.get(node, :children) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  def style_rows(%{style: style}) when is_map(style), do: style_rows(style)
  def style_rows(%{"style" => style}) when is_map(style), do: style_rows(style)

  def style_rows(style) when is_map(style) do
    [
      style_row(style, "stroke_color"),
      style_row(style, "fill_color"),
      style_row(style, "text_color")
    ]
    |> Enum.reject(&is_nil/1)
  end

  def style_row(style, key) when is_map(style) and is_binary(key) do
    value = Map.get(style, key) || Map.get(style, String.to_atom(key))

    if is_integer(value) do
      %{"kind" => key, "color" => value}
    end
  end

end
