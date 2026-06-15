defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Rendered.ViewOutput do
  @moduledoc false

  alias Ide.Debugger.RuntimeViewOutput
  alias IdeWeb.WorkspaceLive.DebuggerPreview.{SvgTextOptions, WireMap}
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types

  @type model_map :: Types.model_map()
  @type rendered_node :: Types.rendered_node()
  @type view_output_row :: Types.view_output_row()
  @type wire_map :: Types.wire_map()
  @type group_style_map :: Types.group_style_map()
  @type view_tree :: Types.view_tree()

  @spec tree(model_map()) :: view_tree() | nil
  def tree(model) when is_map(model) do
    case Map.get(model, "runtime_view_output") || Map.get(model, :runtime_view_output) || [] do
      [_ | _] = ops ->
        {screen_w, screen_h} = screen_size(model)

        %{
          "type" => "windowStack",
          "label" => "",
          "box" => %{"x" => 0, "y" => 0, "w" => screen_w, "h" => screen_h},
          "children" => [
            %{
              "type" => "window",
              "label" => "",
              "id" => 1,
              "children" => [
                %{
                  "type" => "canvasLayer",
                  "label" => "",
                  "id" => 1,
                  "children" => nodes(ops)
                }
              ]
            }
          ]
        }

      _ ->
        nil
    end
  end

  @spec screen_size(model_map()) :: {pos_integer(), pos_integer()}
  def screen_size(model) when is_map(model), do: RuntimeViewOutput.runtime_view_output_screen(model)

  @spec nodes([view_output_row()]) :: [rendered_node()]
  def nodes(ops) when is_list(ops) do
    {nodes, _rest} = nodes_until(ops, false)
    nodes
  end

  @spec nodes_until([view_output_row()], boolean()) :: {[rendered_node()], [view_output_row()]}
  defp nodes_until(rows, stop_on_pop?) when is_list(rows) do
    nodes_until(rows, stop_on_pop?, [])
  end

  defp nodes_until([], _stop_on_pop?, acc), do: {Enum.reverse(acc), []}

  defp nodes_until([row | rest], stop_on_pop?, acc) when is_map(row) do
    case row_kind(row) do
      "pop_context" when stop_on_pop? ->
        {Enum.reverse(acc), rest}

      "pop_context" ->
        nodes_until(rest, stop_on_pop?, acc)

      "push_context" ->
        {group_nodes, remaining} = nodes_until(rest, true)
        {style, children} = split_runtime_view_output_group(group_nodes)

        group =
          %{"type" => "group", "label" => "", "children" => children}
          |> maybe_put_group_style(style)

        nodes_until(remaining, stop_on_pop?, [group | acc])

      kind when kind in ["stroke_color", "fill_color", "text_color"] ->
        nodes_until(rest, stop_on_pop?, [
          style_node(row) | acc
        ])

      _ ->
        case row_node(row) do
          %{} = node -> nodes_until(rest, stop_on_pop?, [node | acc])
          nil -> nodes_until(rest, stop_on_pop?, acc)
        end
    end
  end

  defp nodes_until([_row | rest], stop_on_pop?, acc),
    do: nodes_until(rest, stop_on_pop?, acc)

  @spec split_runtime_view_output_group([rendered_node()]) ::
          {group_style_map(), [rendered_node()]}
  defp split_runtime_view_output_group(nodes) when is_list(nodes) do
    Enum.reduce(nodes, {%{}, []}, fn node, {style, children} ->
      case Map.get(node, "type") do
        "style" ->
          {Map.put(style, Map.get(node, "key"), Map.get(node, "value")), children}

        _ ->
          {style, [node | children]}
      end
    end)
    |> then(fn {style, children} -> {style, Enum.reverse(children)} end)
  end

  @spec maybe_put_group_style(rendered_node(), group_style_map()) :: rendered_node()
  defp maybe_put_group_style(group, style) when is_map(group) and map_size(style) > 0,
    do: Map.put(group, "style", style)

  defp maybe_put_group_style(group, _style), do: group

  @spec style_node(view_output_row()) :: wire_map()
  defp style_node(row) when is_map(row) do
    kind = row_kind(row)

    %{
      "type" => "style",
      "key" => kind,
      "value" =>
        Map.get(row, "color") || Map.get(row, :color) || Map.get(row, "value") ||
          Map.get(row, :value)
    }
  end

  @spec row_kind(view_output_row()) :: String.t()
  defp row_kind(row) when is_map(row),
    do: to_string(Map.get(row, "kind") || Map.get(row, :kind) || "")

  @spec row_node(view_output_row()) :: rendered_node() | nil
  defp row_node(row) when is_map(row) do
    case row_kind(row) do
      "clear" ->
        %{
          "type" => "clear",
          "label" => "",
          "children" => [],
          "color" => WireMap.map_integer(row, "color", 0)
        }
        |> maybe_put_rendered_source(row)

      kind when kind in ["rect", "fill_rect"] ->
        %{
          "type" => if(kind == "rect", do: "rect", else: "fillRect"),
          "label" => "",
          "children" => [],
          "x" => WireMap.map_integer(row, "x", 0),
          "y" => WireMap.map_integer(row, "y", 0),
          "w" => WireMap.map_integer(row, "w", 0),
          "h" => WireMap.map_integer(row, "h", 0),
          "fill" => WireMap.map_integer(row, "fill", 0)
        }
        |> maybe_put_rendered_source(row)

      "round_rect" ->
        %{
          "type" => "roundRect",
          "label" => "",
          "children" => [],
          "x" => WireMap.map_integer(row, "x", 0),
          "y" => WireMap.map_integer(row, "y", 0),
          "w" => WireMap.map_integer(row, "w", 0),
          "h" => WireMap.map_integer(row, "h", 0),
          "radius" => WireMap.map_integer(row, "radius", 0),
          "fill" => WireMap.map_integer(row, "fill", 0)
        }
        |> maybe_put_rendered_source(row)

      "text" ->
        %{
          "type" => "text",
          "label" => "",
          "children" => [],
          "x" => WireMap.map_integer(row, "x", 0),
          "y" => WireMap.map_integer(row, "y", 0),
          "w" => WireMap.map_integer(row, "w", 0),
          "h" => WireMap.map_integer(row, "h", 0),
          "font_id" => WireMap.map_integer(row, "font_id", 0),
          "text" => to_string(Map.get(row, "text") || Map.get(row, :text) || ""),
          "text_align" => SvgTextOptions.normalized_alignment(Map.get(row, "text_align") || Map.get(row, :text_align)),
          "text_overflow" =>
            to_string(
              Map.get(row, "text_overflow") || Map.get(row, :text_overflow) || "word_wrap"
            )
        }
        |> maybe_put_rendered_source(row)

      "line" ->
        %{
          "type" => "line",
          "label" => "",
          "children" => [],
          "x1" => WireMap.map_integer(row, "x1", 0),
          "y1" => WireMap.map_integer(row, "y1", 0),
          "x2" => WireMap.map_integer(row, "x2", 0),
          "y2" => WireMap.map_integer(row, "y2", 0),
          "color" => WireMap.map_integer(row, "color", 0)
        }
        |> maybe_put_rendered_source(row)

      "circle" ->
        %{
          "type" => "circle",
          "label" => "",
          "children" => [],
          "cx" => WireMap.map_integer(row, "cx", 0),
          "cy" => WireMap.map_integer(row, "cy", 0),
          "r" => WireMap.map_integer(row, "r", 0),
          "color" => WireMap.map_integer(row, "color", 0)
        }
        |> maybe_put_rendered_source(row)

      "fill_circle" ->
        %{
          "type" => "fillCircle",
          "label" => "",
          "children" => [],
          "cx" => WireMap.map_integer(row, "cx", 0),
          "cy" => WireMap.map_integer(row, "cy", 0),
          "r" => WireMap.map_integer(row, "r", 0),
          "color" => WireMap.map_integer(row, "color", 0)
        }
        |> maybe_put_rendered_source(row)

      "pixel" ->
        %{
          "type" => "pixel",
          "label" => "",
          "children" => [],
          "x" => WireMap.map_integer(row, "x", 0),
          "y" => WireMap.map_integer(row, "y", 0),
          "color" => WireMap.map_integer(row, "color", 0)
        }
        |> maybe_put_rendered_source(row)

      "text_label" ->
        %{
          "type" => "textLabel",
          "label" => "",
          "children" => [],
          "x" => WireMap.map_integer(row, "x", 0),
          "y" => WireMap.map_integer(row, "y", 0),
          "font_id" => WireMap.map_integer(row, "font_id", 0),
          "text" => to_string(Map.get(row, "text") || Map.get(row, :text) || "")
        }
        |> maybe_put_rendered_source(row)

      "text_int" ->
        %{
          "type" => "textInt",
          "label" => "",
          "children" => [],
          "x" => WireMap.map_integer(row, "x", 0),
          "y" => WireMap.map_integer(row, "y", 0),
          "font_id" => WireMap.map_integer(row, "font_id", 0),
          "text" => to_string(Map.get(row, "text") || Map.get(row, :text) || "")
        }
        |> maybe_put_rendered_source(row)

      "bitmap_in_rect" ->
        %{
          "type" => "bitmapInRect",
          "label" => "",
          "children" => [],
          "bitmap_id" => WireMap.map_integer(row, "bitmap_id", 0),
          "x" => WireMap.map_integer(row, "x", 0),
          "y" => WireMap.map_integer(row, "y", 0),
          "w" => WireMap.map_integer(row, "w", 0),
          "h" => WireMap.map_integer(row, "h", 0)
        }
        |> maybe_put_rendered_source(row)

      "rotated_bitmap" ->
        %{
          "type" => "rotatedBitmap",
          "label" => "",
          "children" => [],
          "bitmap_id" => WireMap.map_integer(row, "bitmap_id", 0),
          "src_w" => WireMap.map_integer(row, "src_w", 0),
          "src_h" => WireMap.map_integer(row, "src_h", 0),
          "angle" => WireMap.map_integer(row, "angle", 0),
          "center_x" => WireMap.map_integer(row, "center_x", 0),
          "center_y" => WireMap.map_integer(row, "center_y", 0)
        }
        |> maybe_put_rendered_source(row)

      "arc" ->
        %{
          "type" => "arc",
          "label" => "",
          "children" => [],
          "x" => WireMap.map_integer(row, "x", 0),
          "y" => WireMap.map_integer(row, "y", 0),
          "w" => WireMap.map_integer(row, "w", 0),
          "h" => WireMap.map_integer(row, "h", 0),
          "start_angle" => WireMap.map_integer(row, "start_angle", 0),
          "end_angle" => WireMap.map_integer(row, "end_angle", 0)
        }
        |> maybe_put_rendered_source(row)

      "fill_radial" ->
        %{
          "type" => "fillRadial",
          "label" => "",
          "children" => [],
          "x" => WireMap.map_integer(row, "x", 0),
          "y" => WireMap.map_integer(row, "y", 0),
          "w" => WireMap.map_integer(row, "w", 0),
          "h" => WireMap.map_integer(row, "h", 0),
          "start_angle" => WireMap.map_integer(row, "start_angle", 0),
          "end_angle" => WireMap.map_integer(row, "end_angle", 0)
        }
        |> maybe_put_rendered_source(row)

      "vector_at" ->
        %{
          "type" => "drawVectorAt",
          "label" => "",
          "children" => [],
          "resource" => Map.get(row, "resource") || Map.get(row, :resource),
          "vector_id" => WireMap.map_integer(row, "vector_id", 0),
          "x" => WireMap.map_integer(row, "x", 0),
          "y" => WireMap.map_integer(row, "y", 0)
        }
        |> maybe_put_rendered_source(row)

      "vector_sequence_at" ->
        %{
          "type" => "drawVectorSequenceAt",
          "label" => "",
          "children" => [],
          "vector_id" => WireMap.map_integer(row, "vector_id", 0),
          "x" => WireMap.map_integer(row, "x", 0),
          "y" => WireMap.map_integer(row, "y", 0)
        }
        |> maybe_put_rendered_source(row)

      "bitmap_sequence_at" ->
        %{
          "type" => "drawBitmapSequenceAt",
          "label" => "",
          "children" => [],
          "animation_id" => WireMap.map_integer(row, "animation_id", 0),
          "x" => WireMap.map_integer(row, "x", 0),
          "y" => WireMap.map_integer(row, "y", 0)
        }
        |> maybe_put_rendered_source(row)

      kind when kind in ["path_filled", "path_outline", "path_outline_open"] ->
        %{
          "type" => path_rendered_type(kind),
          "label" => "",
          "children" => [],
          "points" => Map.get(row, "points") || Map.get(row, :points) || [],
          "offset_x" => WireMap.map_integer(row, "offset_x", 0),
          "offset_y" => WireMap.map_integer(row, "offset_y", 0),
          "rotation" => WireMap.map_integer(row, "rotation", 0)
        }
        |> maybe_put_rendered_source(row)

      _ ->
        nil
    end
  end

  defp path_rendered_type("path_filled"), do: "pathFilled"
  defp path_rendered_type("path_outline"), do: "pathOutline"
  defp path_rendered_type("path_outline_open"), do: "pathOutlineOpen"

  @spec maybe_put_rendered_source(rendered_node(), view_output_row()) :: rendered_node()
  defp maybe_put_rendered_source(node, row) when is_map(node) and is_map(row) do
    case Map.get(row, "source") || Map.get(row, :source) do
      %{} = source -> Map.put(node, "source", source)
      _ -> node
    end
  end

  @spec preview_lines(Types.runtime_input()) :: String.t()
  def preview_lines(runtime) when is_map(runtime) do
    model = Map.get(runtime, :model) || Map.get(runtime, "model") || %{}
    ops = Map.get(model, "runtime_view_output") || Map.get(model, :runtime_view_output) || []

    ops
    |> List.wrap()
    |> Enum.filter(&is_map/1)
    |> Enum.map(&op_line/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> ""
      lines -> Enum.join(lines, "\n")
    end
  end

  @spec op_line(view_output_row()) :: String.t()
  defp op_line(op) when is_map(op) do
    kind = to_string(Map.get(op, "kind") || Map.get(op, :kind) || "")

    case kind do
      "clear" ->
        "- clear [#{WireMap.map_integer(op, "color", 0)}]"

      "round_rect" ->
        "- roundRect [x=#{WireMap.map_integer(op, "x", 0)}, y=#{WireMap.map_integer(op, "y", 0)}, w=#{WireMap.map_integer(op, "w", 0)}, h=#{WireMap.map_integer(op, "h", 0)}, r=#{WireMap.map_integer(op, "radius", 0)}, fill=#{WireMap.map_integer(op, "fill", 0)}]"

      "rect" ->
        "- rect [x=#{WireMap.map_integer(op, "x", 0)}, y=#{WireMap.map_integer(op, "y", 0)}, w=#{WireMap.map_integer(op, "w", 0)}, h=#{WireMap.map_integer(op, "h", 0)}, fill=#{WireMap.map_integer(op, "fill", 0)}]"

      "line" ->
        "- line [#{WireMap.map_integer(op, "x1", 0)}, #{WireMap.map_integer(op, "y1", 0)} -> #{WireMap.map_integer(op, "x2", 0)}, #{WireMap.map_integer(op, "y2", 0)}]"

      "pixel" ->
        "- pixel [#{WireMap.map_integer(op, "x", 0)}, #{WireMap.map_integer(op, "y", 0)}, c=#{WireMap.map_integer(op, "color", 0)}]"

      "text_int" ->
        text = to_string(Map.get(op, "text") || Map.get(op, :text) || "")

        "- textInt [x=#{WireMap.map_integer(op, "x", 0)}, y=#{WireMap.map_integer(op, "y", 0)}, #{text}]"

      "text_label" ->
        text = to_string(Map.get(op, "text") || Map.get(op, :text) || "")

        "- textLabel [x=#{WireMap.map_integer(op, "x", 0)}, y=#{WireMap.map_integer(op, "y", 0)}, #{text}]"

      "unresolved" ->
        node_type = to_string(Map.get(op, "node_type") || Map.get(op, :node_type) || "node")
        provided = WireMap.map_integer(op, "provided_int_count", 0)
        required = WireMap.map_integer(op, "required_int_count", 0)
        label = to_string(Map.get(op, "label") || Map.get(op, :label) || "")
        "- unresolved [#{node_type}, ints=#{provided}/#{required}, #{label}]"

      _ ->
        ""
    end
  end

  defp op_line(_op), do: ""
end
