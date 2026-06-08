defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Rendered.Core do
  @moduledoc false
  @dialyzer :no_match

  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Resources.ResourceStore
  alias Ide.Resources.PdcDecoder
  alias Ide.Projects.Project
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Util
  @spec runtime_json(Ide.Debugger.Types.execution_model()) :: String.t()
  def runtime_json(runtime) when is_map(runtime), do: Jason.encode!(runtime, pretty: true)
  def runtime_json(_runtime), do: "{}"

  @spec rendered_tree(Ide.Debugger.Types.execution_model()) ::
          Ide.Debugger.Types.rendered_tree() | nil
  def rendered_tree(%{} = runtime) do
    model = runtime_model(runtime)

    case runtime_rendered_tree(runtime, model) do
      %{} = tree ->
        tree
        |> reject_placeholder_rendered_tree()
        |> normalize_rendered_tree_or_nil()

      _ ->
        ei = Ide.Debugger.RuntimeArtifacts.require_introspect(model)

        model
        |> parser_view_tree()
        |> discard_parser_expression_view_tree(ei)
        |> normalize_rendered_tree_or_nil()
    end
  end

  def rendered_tree(_runtime), do: nil

  @spec runtime_rendered_tree(Ide.Debugger.Types.execution_model(), Ide.Debugger.Types.wire_map()) ::
          Types.view_tree() | nil
  defp runtime_rendered_tree(runtime, model) when is_map(runtime) and is_map(model) do
    view_tree = Map.get(runtime, :view_tree) || Map.get(runtime, "view_tree")

    view_tree =
      if Ide.Debugger.StepExecution.placeholder_view_tree?(view_tree), do: %{}, else: view_tree

    ei = RuntimeArtifacts.require_introspect(model)

    stored_rows =
      Map.get(model, "runtime_view_output") || Map.get(model, :runtime_view_output) || []

    had_stored_rows? = stored_rows != []

    preview_model =
      case Map.get(model, "runtime_model") || Map.get(model, :runtime_model) do
        %{} = runtime_model -> runtime_model
        _ -> model
      end

    execution_model = RuntimeArtifacts.execution_model(runtime)

    {stored_rows, view_tree} =
      case Ide.Debugger.StepExecution.maybe_executor_view_preview(
             execution_model,
             model,
             :watch,
             stored_rows
           ) do
        {:ok, %{view_output: rows, view_tree: fresh_tree}} ->
          {rows, fresh_tree || view_tree || %{}}

        :skip ->
          {stored_rows, view_tree || %{}}
      end

    refreshed_rows =
      Ide.Debugger.StepExecution.resolve_runtime_view_output(
        execution_model,
        view_tree,
        preview_model,
        stored_rows
      )

    output_tree = runtime_view_output_tree(Map.put(model, "runtime_view_output", refreshed_rows))

    cond do
      not had_stored_rows? and concrete_rendered_view_tree?(view_tree, ei) ->
        view_tree

      output_tree != nil and
          not Ide.Debugger.StepExecution.stale_runtime_view_output?(preview_model, refreshed_rows) ->
        output_tree

      concrete_rendered_view_tree?(view_tree, ei) ->
        view_tree

      true ->
        nil
    end
  end

  defp runtime_rendered_tree(_runtime, _model), do: nil

  @spec concrete_rendered_view_tree?(Types.view_tree(), map()) :: boolean()
  defp concrete_rendered_view_tree?(%{"type" => "tuple2"} = tree, _ei),
    do: match?({:ok, _node}, normalize_rendered_ui_value(tree))

  defp concrete_rendered_view_tree?(tree, ei) when is_map(tree) and map_size(tree) > 0 do
    not Ide.Debugger.StepExecution.placeholder_view_tree?(tree) and
      not parser_expression_view_tree?(tree, ei)
  end

  defp concrete_rendered_view_tree?(_tree, _ei), do: false

  @spec discard_parser_expression_view_tree(Types.view_tree(), Ide.Debugger.Types.elm_introspect()) ::
          Types.view_tree() | nil
  defp discard_parser_expression_view_tree(tree, ei) when is_map(tree) do
    if parser_expression_view_tree?(tree, ei), do: nil, else: tree
  end

  defp discard_parser_expression_view_tree(_tree, _ei), do: nil

  @spec parser_expression_view_tree?(Types.view_tree(), map()) :: boolean()
  defp parser_expression_view_tree?(%{"type" => "tuple2"} = tree, _ei),
    do: not match?({:ok, _node}, normalize_rendered_ui_value(tree))

  defp parser_expression_view_tree?(tree, ei) when is_map(tree) and is_map(ei),
    do: ElmEx.DebuggerContract.parser_expression_view_tree_node?(tree, ei)

  defp parser_expression_view_tree?(_tree, _ei), do: false

  @spec runtime_view_output_tree(Ide.Debugger.Types.wire_map()) :: Types.view_tree() | nil
  defp runtime_view_output_tree(model) when is_map(model) do
    case Map.get(model, "runtime_view_output") || Map.get(model, :runtime_view_output) || [] do
      [_ | _] = ops ->
        {screen_w, screen_h} = runtime_view_output_screen(model)

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
                  "children" => runtime_view_output_nodes(ops)
                }
              ]
            }
          ]
        }

      _ ->
        nil
    end
  end

  @spec runtime_view_output_screen(map()) :: {pos_integer(), pos_integer()}
  defp runtime_view_output_screen(model) when is_map(model) do
    runtime_model =
      case Map.get(model, "runtime_model") || Map.get(model, :runtime_model) do
        %{} = value -> value
        _ -> model
      end

    {
      positive_integer_value(
        Map.get(runtime_model, "screenW") || Map.get(runtime_model, :screenW),
        144
      ),
      positive_integer_value(
        Map.get(runtime_model, "screenH") || Map.get(runtime_model, :screenH),
        168
      )
    }
  end

  @spec positive_integer_value(Types.wire_input(), pos_integer()) :: pos_integer()
  defp positive_integer_value(value, _fallback) when is_integer(value) and value > 0, do: value

  defp positive_integer_value(value, _fallback) when is_float(value) and value > 0,
    do: trunc(value)

  defp positive_integer_value(value, fallback) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> fallback
    end
  end

  defp positive_integer_value(_value, fallback), do: fallback

  @spec runtime_view_output_nodes([Ide.Debugger.Types.view_output_row()]) ::
          [Ide.Debugger.Types.view_output_row()]
  defp runtime_view_output_nodes(ops) when is_list(ops) do
    {nodes, _rest} = runtime_view_output_nodes_until(ops, false)
    nodes
  end

  @spec runtime_view_output_nodes_until([map()], boolean()) :: {[map()], [map()]}
  defp runtime_view_output_nodes_until(rows, stop_on_pop?) when is_list(rows) do
    runtime_view_output_nodes_until(rows, stop_on_pop?, [])
  end

  defp runtime_view_output_nodes_until([], _stop_on_pop?, acc), do: {Enum.reverse(acc), []}

  defp runtime_view_output_nodes_until([row | rest], stop_on_pop?, acc) when is_map(row) do
    case runtime_view_output_kind(row) do
      "pop_context" when stop_on_pop? ->
        {Enum.reverse(acc), rest}

      "pop_context" ->
        runtime_view_output_nodes_until(rest, stop_on_pop?, acc)

      "push_context" ->
        {group_nodes, remaining} = runtime_view_output_nodes_until(rest, true)
        {style, children} = split_runtime_view_output_group(group_nodes)

        group =
          %{"type" => "group", "label" => "", "children" => children}
          |> maybe_put_group_style(style)

        runtime_view_output_nodes_until(remaining, stop_on_pop?, [group | acc])

      kind when kind in ["stroke_color", "fill_color", "text_color"] ->
        runtime_view_output_nodes_until(rest, stop_on_pop?, [
          runtime_view_output_style_node(row) | acc
        ])

      _ ->
        case runtime_view_output_node(row) do
          %{} = node -> runtime_view_output_nodes_until(rest, stop_on_pop?, [node | acc])
          nil -> runtime_view_output_nodes_until(rest, stop_on_pop?, acc)
        end
    end
  end

  defp runtime_view_output_nodes_until([_row | rest], stop_on_pop?, acc),
    do: runtime_view_output_nodes_until(rest, stop_on_pop?, acc)

  @spec split_runtime_view_output_group([map()]) :: {map(), [map()]}
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

  @spec maybe_put_group_style(map(), map()) :: map()
  defp maybe_put_group_style(group, style) when is_map(group) and map_size(style) > 0,
    do: Map.put(group, "style", style)

  defp maybe_put_group_style(group, _style), do: group

  @spec runtime_view_output_style_node(map()) :: map()
  defp runtime_view_output_style_node(row) when is_map(row) do
    kind = runtime_view_output_kind(row)

    %{
      "type" => "style",
      "key" => kind,
      "value" =>
        Map.get(row, "color") || Map.get(row, :color) || Map.get(row, "value") ||
          Map.get(row, :value)
    }
  end

  @spec runtime_view_output_kind(map()) :: String.t()
  defp runtime_view_output_kind(row) when is_map(row),
    do: to_string(Map.get(row, "kind") || Map.get(row, :kind) || "")

  @spec runtime_view_output_node(map()) :: map() | nil
  defp runtime_view_output_node(row) when is_map(row) do
    case runtime_view_output_kind(row) do
      "clear" ->
        %{
          "type" => "clear",
          "label" => "",
          "children" => [],
          "color" => map_integer_value(row, "color", 0)
        }
        |> maybe_put_rendered_source(row)

      kind when kind in ["rect", "fill_rect"] ->
        %{
          "type" => if(kind == "rect", do: "rect", else: "fillRect"),
          "label" => "",
          "children" => [],
          "x" => map_integer_value(row, "x", 0),
          "y" => map_integer_value(row, "y", 0),
          "w" => map_integer_value(row, "w", 0),
          "h" => map_integer_value(row, "h", 0),
          "fill" => map_integer_value(row, "fill", 0)
        }
        |> maybe_put_rendered_source(row)

      "round_rect" ->
        %{
          "type" => "roundRect",
          "label" => "",
          "children" => [],
          "x" => map_integer_value(row, "x", 0),
          "y" => map_integer_value(row, "y", 0),
          "w" => map_integer_value(row, "w", 0),
          "h" => map_integer_value(row, "h", 0),
          "radius" => map_integer_value(row, "radius", 0),
          "fill" => map_integer_value(row, "fill", 0)
        }
        |> maybe_put_rendered_source(row)

      "text" ->
        %{
          "type" => "text",
          "label" => "",
          "children" => [],
          "x" => map_integer_value(row, "x", 0),
          "y" => map_integer_value(row, "y", 0),
          "w" => map_integer_value(row, "w", 0),
          "h" => map_integer_value(row, "h", 0),
          "font_id" => map_integer_value(row, "font_id", 0),
          "text" => to_string(Map.get(row, "text") || Map.get(row, :text) || ""),
          "text_align" => rendered_text_alignment(Map.get(row, "text_align") || Map.get(row, :text_align)),
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
          "x1" => map_integer_value(row, "x1", 0),
          "y1" => map_integer_value(row, "y1", 0),
          "x2" => map_integer_value(row, "x2", 0),
          "y2" => map_integer_value(row, "y2", 0),
          "color" => map_integer_value(row, "color", 0)
        }
        |> maybe_put_rendered_source(row)

      "circle" ->
        %{
          "type" => "circle",
          "label" => "",
          "children" => [],
          "cx" => map_integer_value(row, "cx", 0),
          "cy" => map_integer_value(row, "cy", 0),
          "r" => map_integer_value(row, "r", 0),
          "color" => map_integer_value(row, "color", 0)
        }
        |> maybe_put_rendered_source(row)

      "fill_circle" ->
        %{
          "type" => "fillCircle",
          "label" => "",
          "children" => [],
          "cx" => map_integer_value(row, "cx", 0),
          "cy" => map_integer_value(row, "cy", 0),
          "r" => map_integer_value(row, "r", 0),
          "color" => map_integer_value(row, "color", 0)
        }
        |> maybe_put_rendered_source(row)

      "pixel" ->
        %{
          "type" => "pixel",
          "label" => "",
          "children" => [],
          "x" => map_integer_value(row, "x", 0),
          "y" => map_integer_value(row, "y", 0),
          "color" => map_integer_value(row, "color", 0)
        }
        |> maybe_put_rendered_source(row)

      "text_label" ->
        %{
          "type" => "textLabel",
          "label" => "",
          "children" => [],
          "x" => map_integer_value(row, "x", 0),
          "y" => map_integer_value(row, "y", 0),
          "font_id" => map_integer_value(row, "font_id", 0),
          "text" => to_string(Map.get(row, "text") || Map.get(row, :text) || "")
        }
        |> maybe_put_rendered_source(row)

      "text_int" ->
        %{
          "type" => "textInt",
          "label" => "",
          "children" => [],
          "x" => map_integer_value(row, "x", 0),
          "y" => map_integer_value(row, "y", 0),
          "font_id" => map_integer_value(row, "font_id", 0),
          "text" => to_string(Map.get(row, "text") || Map.get(row, :text) || "")
        }
        |> maybe_put_rendered_source(row)

      "bitmap_in_rect" ->
        %{
          "type" => "bitmapInRect",
          "label" => "",
          "children" => [],
          "bitmap_id" => map_integer_value(row, "bitmap_id", 0),
          "x" => map_integer_value(row, "x", 0),
          "y" => map_integer_value(row, "y", 0),
          "w" => map_integer_value(row, "w", 0),
          "h" => map_integer_value(row, "h", 0)
        }
        |> maybe_put_rendered_source(row)

      "rotated_bitmap" ->
        %{
          "type" => "rotatedBitmap",
          "label" => "",
          "children" => [],
          "bitmap_id" => map_integer_value(row, "bitmap_id", 0),
          "src_w" => map_integer_value(row, "src_w", 0),
          "src_h" => map_integer_value(row, "src_h", 0),
          "angle" => map_integer_value(row, "angle", 0),
          "center_x" => map_integer_value(row, "center_x", 0),
          "center_y" => map_integer_value(row, "center_y", 0)
        }
        |> maybe_put_rendered_source(row)

      "arc" ->
        %{
          "type" => "arc",
          "label" => "",
          "children" => [],
          "x" => map_integer_value(row, "x", 0),
          "y" => map_integer_value(row, "y", 0),
          "w" => map_integer_value(row, "w", 0),
          "h" => map_integer_value(row, "h", 0),
          "start_angle" => map_integer_value(row, "start_angle", 0),
          "end_angle" => map_integer_value(row, "end_angle", 0)
        }
        |> maybe_put_rendered_source(row)

      "fill_radial" ->
        %{
          "type" => "fillRadial",
          "label" => "",
          "children" => [],
          "x" => map_integer_value(row, "x", 0),
          "y" => map_integer_value(row, "y", 0),
          "w" => map_integer_value(row, "w", 0),
          "h" => map_integer_value(row, "h", 0),
          "start_angle" => map_integer_value(row, "start_angle", 0),
          "end_angle" => map_integer_value(row, "end_angle", 0)
        }
        |> maybe_put_rendered_source(row)

      "vector_at" ->
        %{
          "type" => "drawVectorAt",
          "label" => "",
          "children" => [],
          "resource" => Map.get(row, "resource") || Map.get(row, :resource),
          "vector_id" => map_integer_value(row, "vector_id", 0),
          "x" => map_integer_value(row, "x", 0),
          "y" => map_integer_value(row, "y", 0)
        }
        |> maybe_put_rendered_source(row)

      "vector_sequence_at" ->
        %{
          "type" => "drawVectorSequenceAt",
          "label" => "",
          "children" => [],
          "vector_id" => map_integer_value(row, "vector_id", 0),
          "x" => map_integer_value(row, "x", 0),
          "y" => map_integer_value(row, "y", 0)
        }
        |> maybe_put_rendered_source(row)

      "bitmap_sequence_at" ->
        %{
          "type" => "drawBitmapSequenceAt",
          "label" => "",
          "children" => [],
          "animation_id" => map_integer_value(row, "animation_id", 0),
          "x" => map_integer_value(row, "x", 0),
          "y" => map_integer_value(row, "y", 0)
        }
        |> maybe_put_rendered_source(row)

      kind when kind in ["path_filled", "path_outline", "path_outline_open"] ->
        %{
          "type" => path_rendered_type(kind),
          "label" => "",
          "children" => [],
          "points" => Map.get(row, "points") || Map.get(row, :points) || [],
          "offset_x" => map_integer_value(row, "offset_x", 0),
          "offset_y" => map_integer_value(row, "offset_y", 0),
          "rotation" => map_integer_value(row, "rotation", 0)
        }
        |> maybe_put_rendered_source(row)

      _ ->
        nil
    end
  end

  defp path_rendered_type("path_filled"), do: "pathFilled"
  defp path_rendered_type("path_outline"), do: "pathOutline"
  defp path_rendered_type("path_outline_open"), do: "pathOutlineOpen"

  @spec maybe_put_rendered_source(map(), map()) :: map()
  defp maybe_put_rendered_source(node, row) when is_map(node) and is_map(row) do
    case Map.get(row, "source") || Map.get(row, :source) do
      %{} = source -> Map.put(node, "source", source)
      _ -> node
    end
  end

  @spec rendered_node_bounds(
          Types.rendered_node() | map(),
          String.t(),
          integer(),
          integer(),
          Project.t() | nil
        ) :: map() | nil
  def rendered_node_bounds(tree, path, screen_w, screen_h, project \\ nil)

  def rendered_node_bounds(tree, path, screen_w, screen_h, project)
      when is_map(tree) and is_binary(path) do
    tree
    |> rendered_node_at_path(path)
    |> rendered_bounds_for_node(screen_w, screen_h, project)
  end

  def rendered_node_bounds(_tree, _path, _screen_w, _screen_h, _project), do: nil

  @spec rendered_node_at_path(Types.view_tree(), String.t()) :: Types.rendered_node() | nil
  defp rendered_node_at_path(tree, path) when is_map(tree) and is_binary(path) do
    indexes =
      path
      |> String.split(".", trim: true)
      |> Enum.map(&Integer.parse/1)

    case indexes do
      [{0, ""} | rest] -> rendered_node_at_indexes(tree, rest)
      [] -> tree
      _ -> nil
    end
  end

  @spec rendered_node_at_indexes(Types.rendered_node(), [{integer(), String.t()}]) ::
          Types.rendered_node() | nil
  defp rendered_node_at_indexes(node, []) when is_map(node), do: node

  defp rendered_node_at_indexes(node, [{index, ""} | rest]) when is_map(node) and index >= 0 do
    children = Map.get(node, "children") || Map.get(node, :children) || []

    children
    |> Enum.filter(&is_map/1)
    |> Enum.at(index)
    |> rendered_node_at_indexes(rest)
  end

  defp rendered_node_at_indexes(_node, _indexes), do: nil

  @spec rendered_bounds_for_node(Types.rendered_node(), integer(), integer(), Project.t() | nil) ::
          map() | nil
  defp rendered_bounds_for_node(node, screen_w, screen_h, project) when is_map(node) do
    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "")

    case type do
      "clear" ->
        w = if is_integer(screen_w), do: screen_w, else: 0
        h = if is_integer(screen_h), do: screen_h, else: 0
        %{x: 0, y: 0, w: max(w, 1), h: max(h, 1)}

      "roundRect" ->
        rect_bounds(node)

      "rect" ->
        rect_bounds(node)

      "fillRect" ->
        rect_bounds(node)

      "text" ->
        rect_bounds(node)

      "bitmapInRect" ->
        rect_bounds(node)

      "arc" ->
        rect_bounds(node)

      "fillRadial" ->
        rect_bounds(node)

      "pathFilled" ->
        path_bounds(node)

      "pathOutline" ->
        path_bounds(node)

      "pathOutlineOpen" ->
        path_bounds(node)

      "line" ->
        line_bounds(node)

      "pixel" ->
        with x when is_integer(x) <- Util.map_integer(node, :x),
             y when is_integer(y) <- Util.map_integer(node, :y) do
          %{x: x, y: y, w: 1, h: 1}
        else
          _ -> nil
        end

      "circle" ->
        circle_bounds(node)

      "fillCircle" ->
        circle_bounds(node)

      "textInt" ->
        text_point_bounds(node, 48, 14)

      "textLabel" ->
        text_point_bounds(node, 56, 12)

      "rotatedBitmap" ->
        rotated_bitmap_bounds(node)

      "drawVectorAt" ->
        vector_at_bounds(node, project, :image)

      "drawVectorSequenceAt" ->
        vector_at_bounds(node, project, :sequence)

      "drawBitmapSequenceAt" ->
        animation_at_bounds(node, project)

      _ ->
        aggregate_child_bounds(node, screen_w, screen_h, project)
    end
  end

  defp rendered_bounds_for_node(_node, _screen_w, _screen_h, _project), do: nil

  @spec animation_at_bounds(map(), Project.t() | nil) :: map() | nil
  defp animation_at_bounds(node, %Project{} = project) when is_map(node) do
    with animation_id when is_integer(animation_id) and animation_id >= 1 <-
           Util.map_integer(node, :animation_id),
         x when is_integer(x) <- Util.map_integer(node, :x),
         y when is_integer(y) <- Util.map_integer(node, :y),
         {:ok, path} <- ResourceStore.animation_file_path_by_id(project, animation_id),
         {:ok, probe} <- Ide.Resources.ApngProbe.probe(path) do
      %{x: x, y: y, w: max(probe.width, 1), h: max(probe.height, 1)}
    else
      _ -> nil
    end
  end

  defp animation_at_bounds(_node, _project), do: nil

  @spec vector_at_bounds(map(), Project.t() | nil, :image | :sequence) :: map() | nil
  defp vector_at_bounds(node, project, kind) when is_map(node) and kind in [:image, :sequence] do
    with x when is_integer(x) <- Util.map_integer(node, :x),
         y when is_integer(y) <- Util.map_integer(node, :y),
         {:ok, {w, h}} <- vector_canvas_size(node, project, kind) do
      %{x: x, y: y, w: max(w, 1), h: max(h, 1)}
    else
      _ -> nil
    end
  end

  @spec vector_canvas_size(map(), Project.t() | nil, :image | :sequence) ::
          {:ok, {integer(), integer()}} | :error
  defp vector_canvas_size(node, %Project{} = project, kind) when is_map(node) do
    with vector_id when is_integer(vector_id) and vector_id >= 1 <-
           Util.map_integer(node, :vector_id),
         {:ok, path} <- ResourceStore.vector_file_path_by_id(project, vector_id),
         {:ok, bytes} <- File.read(path),
         {:ok, {w, h}} <- PdcDecoder.decode_canvas_size(bytes, kind) do
      {:ok, {w, h}}
    else
      _ -> :error
    end
  end

  defp vector_canvas_size(_node, _project, _kind), do: :error

  @spec rect_bounds(Types.rendered_node()) :: Types.bounds_map() | nil
  defp rect_bounds(node) when is_map(node) do
    with x when is_integer(x) <- Util.map_integer(node, :x),
         y when is_integer(y) <- Util.map_integer(node, :y),
         w when is_integer(w) <- Util.map_integer(node, :w),
         h when is_integer(h) <- Util.map_integer(node, :h) do
      %{x: x, y: y, w: max(w, 1), h: max(h, 1)}
    else
      _ -> nil
    end
  end

  @spec line_bounds(Types.rendered_node()) :: Types.bounds_map() | nil
  defp line_bounds(node) when is_map(node) do
    with x1 when is_integer(x1) <- Util.map_integer(node, :x1),
         y1 when is_integer(y1) <- Util.map_integer(node, :y1),
         x2 when is_integer(x2) <- Util.map_integer(node, :x2),
         y2 when is_integer(y2) <- Util.map_integer(node, :y2) do
      x = min(x1, x2)
      y = min(y1, y2)
      %{x: x, y: y, w: max(abs(x2 - x1), 1), h: max(abs(y2 - y1), 1)}
    else
      _ -> nil
    end
  end

  @spec circle_bounds(Types.rendered_node()) :: Types.bounds_map() | nil
  defp circle_bounds(node) when is_map(node) do
    with cx when is_integer(cx) <- Util.map_integer(node, :cx),
         cy when is_integer(cy) <- Util.map_integer(node, :cy),
         r when is_integer(r) <- Util.map_integer(node, :r) do
      radius = max(r, 1)
      %{x: cx - radius, y: cy - radius, w: radius * 2, h: radius * 2}
    else
      _ -> nil
    end
  end

  @spec text_point_bounds(Types.rendered_node(), integer(), integer()) ::
          Types.bounds_map() | nil
  defp text_point_bounds(node, default_w, default_h) when is_map(node) do
    with x when is_integer(x) <- Util.map_integer(node, :x),
         y when is_integer(y) <- Util.map_integer(node, :y) do
      %{x: x, y: y - default_h, w: default_w, h: default_h}
    else
      _ -> nil
    end
  end

  @spec rotated_bitmap_bounds(Types.rendered_node()) :: Types.bounds_map() | nil
  defp rotated_bitmap_bounds(node) when is_map(node) do
    with center_x when is_integer(center_x) <- Util.map_integer(node, :center_x),
         center_y when is_integer(center_y) <- Util.map_integer(node, :center_y),
         src_w when is_integer(src_w) <- Util.map_integer(node, :src_w),
         src_h when is_integer(src_h) <- Util.map_integer(node, :src_h) do
      angle = Util.map_integer(node, :angle) || 0

      rotated_points_bounds(
        [
          {-src_w / 2.0, -src_h / 2.0},
          {src_w / 2.0, -src_h / 2.0},
          {src_w / 2.0, src_h / 2.0},
          {-src_w / 2.0, src_h / 2.0}
        ],
        center_x,
        center_y,
        angle
      )
    else
      _ -> nil
    end
  end

  @spec path_bounds(Types.rendered_node()) :: Types.bounds_map() | nil
  defp path_bounds(node) when is_map(node) do
    payload = path_payload_from_children(node)
    points = Map.get(node, "points") || Map.get(node, :points) || Map.get(payload, :points, [])
    offset_x = Util.map_integer(node, :offset_x) || Map.get(payload, :offset_x, 0)
    offset_y = Util.map_integer(node, :offset_y) || Map.get(payload, :offset_y, 0)
    rotation = Util.map_integer(node, :rotation) || Map.get(payload, :rotation, 0)

    points
    |> normalize_path_points()
    |> case do
      [] ->
        nil

      normalized ->
        rotated_points_bounds(normalized, offset_x, offset_y, rotation)
    end
  end

  @spec rotated_points_bounds([{number(), number()}], number(), number(), integer()) ::
          map() | nil
  defp rotated_points_bounds(points, offset_x, offset_y, rotation)
       when is_list(points) and is_number(offset_x) and is_number(offset_y) and
              is_integer(rotation) do
    rotation_rad = rotation * 2.0 * :math.pi() / 65_536.0
    cos_r = :math.cos(rotation_rad)
    sin_r = :math.sin(rotation_rad)

    transformed =
      Enum.map(points, fn {x, y} ->
        xr = x * cos_r - y * sin_r
        yr = x * sin_r + y * cos_r
        {xr + offset_x, yr + offset_y}
      end)

    case transformed do
      [] ->
        nil

      _ ->
        xs = Enum.map(transformed, fn {x, _y} -> x end)
        ys = Enum.map(transformed, fn {_x, y} -> y end)
        min_x = Enum.min(xs)
        min_y = Enum.min(ys)
        max_x = Enum.max(xs)
        max_y = Enum.max(ys)

        %{
          x: rendered_bounds_number(Float.floor(min_x, 2)),
          y: rendered_bounds_number(Float.floor(min_y, 2)),
          w: rendered_bounds_number(max(Float.ceil(max_x - min_x, 2), 1)),
          h: rendered_bounds_number(max(Float.ceil(max_y - min_y, 2), 1))
        }
    end
  end

  @spec rendered_bounds_number(number()) :: number()
  defp rendered_bounds_number(value) when is_float(value) do
    rounded = round(value)
    if Float.round(value, 6) == rounded * 1.0, do: rounded, else: value
  end

  defp rendered_bounds_number(value), do: value

  @spec path_payload_from_children(map()) :: map()
  defp path_payload_from_children(node) when is_map(node) do
    case Map.get(node, "children") || Map.get(node, :children) || [] do
      [%{"points" => points} = payload | _] ->
        %{
          points: points,
          offset_x: Util.map_integer(payload, :offset_x) || 0,
          offset_y: Util.map_integer(payload, :offset_y) || 0,
          rotation: Util.map_integer(payload, :rotation) || 0
        }

      [%{points: points} = payload | _] ->
        %{
          points: points,
          offset_x: Util.map_integer(payload, :offset_x) || 0,
          offset_y: Util.map_integer(payload, :offset_y) || 0,
          rotation: Util.map_integer(payload, :rotation) || 0
        }

      [payload | _] ->
        path_payload_from_node(payload)

      _ ->
        %{}
    end
  end

  @spec path_payload_from_node(Types.rendered_node()) :: map()
  defp path_payload_from_node(payload) do
    with {:ok, [points_node, offset_node, rotation_node]} <- normalized_payload_args(payload, 3),
         points when points != [] <- normalize_path_points_from_node(points_node),
         {offset_x, offset_y} <- normalize_path_point(offset_node),
         rotation when is_integer(rotation) <- rendered_expr_scalar(rotation_node) do
      %{points: points, offset_x: offset_x, offset_y: offset_y, rotation: rotation}
    else
      _ -> %{}
    end
  end

  @spec normalize_path_points_from_node(Types.rendered_node()) :: [{integer(), integer()}]
  defp normalize_path_points_from_node(%{"type" => "List", "children" => points})
       when is_list(points) do
    normalize_path_points(points)
  end

  defp normalize_path_points_from_node(%{type: "List", children: points}) when is_list(points) do
    normalize_path_points(points)
  end

  defp normalize_path_points_from_node(points), do: normalize_path_points(points)

  @spec normalize_path_points(list()) :: [{integer(), integer()}]
  defp normalize_path_points(points) when is_list(points) do
    points
    |> Enum.map(&normalize_path_point/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_path_points(_points), do: []

  @spec normalize_path_point(map() | list()) :: {integer(), integer()} | nil
  defp normalize_path_point([x, y]) when is_integer(x) and is_integer(y), do: {x, y}

  defp normalize_path_point(%{"x" => x, "y" => y}) when is_integer(x) and is_integer(y),
    do: {x, y}

  defp normalize_path_point(%{x: x, y: y}) when is_integer(x) and is_integer(y), do: {x, y}

  defp normalize_path_point(%{"type" => "tuple2", "children" => [x_node, y_node]}) do
    x = rendered_expr_scalar(x_node)
    y = rendered_expr_scalar(y_node)
    if is_integer(x) and is_integer(y), do: {x, y}, else: nil
  end

  defp normalize_path_point(%{type: "tuple2", children: [x_node, y_node]}) do
    x = rendered_expr_scalar(x_node)
    y = rendered_expr_scalar(y_node)
    if is_integer(x) and is_integer(y), do: {x, y}, else: nil
  end

  defp normalize_path_point(_point), do: nil

  @spec aggregate_child_bounds(map(), integer(), integer(), Project.t() | nil) :: map() | nil
  defp aggregate_child_bounds(node, screen_w, screen_h, project) when is_map(node) do
    node
    |> Map.get("children", Map.get(node, :children, []))
    |> Enum.filter(&is_map/1)
    |> Enum.map(&rendered_bounds_for_node(&1, screen_w, screen_h, project))
    |> Enum.reject(&is_nil/1)
    |> union_bounds()
  end

  @spec union_bounds([Types.bounds_map()]) :: Types.bounds_map() | nil
  defp union_bounds([]), do: nil

  defp union_bounds([first | rest]) do
    Enum.reduce(rest, first, fn box, acc ->
      min_x = min(acc.x, box.x)
      min_y = min(acc.y, box.y)
      max_x = max(acc.x + acc.w, box.x + box.w)
      max_y = max(acc.y + acc.h, box.y + box.h)
      %{x: min_x, y: min_y, w: max(max_x - min_x, 1), h: max(max_y - min_y, 1)}
    end)
  end

  @spec reject_placeholder_rendered_tree(Types.view_tree() | nil) :: Types.view_tree() | nil
  defp reject_placeholder_rendered_tree(tree) do
    if Ide.Debugger.StepExecution.placeholder_view_tree?(tree), do: nil, else: tree
  end

  @spec normalize_rendered_tree_or_nil(Types.view_tree() | nil) :: Types.view_tree() | nil
  defp normalize_rendered_tree_or_nil(nil), do: nil

  defp normalize_rendered_tree_or_nil(%{} = tree) do
    case normalize_rendered_ui_value(tree) do
      {:ok, node} -> node
      :error -> tree
    end
  end

  @spec normalize_rendered_tree(Types.view_tree()) :: Types.view_tree()
  defp normalize_rendered_tree(tree) when is_map(tree) do
    case normalize_rendered_tree_or_nil(tree) do
      %{} = node -> node
      nil -> tree
    end
  end

  @spec normalize_rendered_ui_value(Types.runtime_value()) :: {:ok, map()} | :error
  defp normalize_rendered_ui_value(%{"type" => type, "children" => children} = value)
       when is_binary(type) and is_list(children) and type not in ["tuple2", "List"] do
    value =
      value
      |> Map.put("children", Enum.map(children, &normalize_rendered_child/1))
      |> normalize_rendered_text_field()
      |> promote_rendered_node_args()

    {:ok, value}
  end

  defp normalize_rendered_ui_value(value) do
    with {:ok, tag, windows} when tag in [1, 1000] <- normalized_tagged_tuple(value),
         {:ok, windows} <- normalized_list_values(windows),
         {:ok, window_nodes} <-
           normalize_rendered_list(windows, &normalize_rendered_window_node/1) do
      {:ok, %{"type" => "windowStack", "label" => "", "children" => window_nodes}}
    else
      _ -> :error
    end
  end

  @spec normalize_rendered_window_node(Types.runtime_value()) :: {:ok, map()} | :error
  defp normalize_rendered_window_node(value) do
    with {:ok, tag, payload} when tag in [1, 1001] <- normalized_tagged_tuple(value),
         {:ok, [id, layers]} <- normalized_payload_args(payload, 2),
         {:ok, layers} <- normalized_list_values(layers),
         {:ok, layer_nodes} <- normalize_rendered_list(layers, &normalize_rendered_layer_node/1) do
      {:ok,
       %{
         "type" => "window",
         "label" => "",
         "id" => rendered_expr_scalar(normalize_rendered_child(id)),
         "children" => layer_nodes
       }}
    else
      _ -> :error
    end
  end

  @spec normalize_rendered_layer_node(Types.runtime_value()) :: {:ok, map()} | :error
  defp normalize_rendered_layer_node(value) do
    with {:ok, tag, payload} when tag in [1, 1002] <- normalized_tagged_tuple(value),
         {:ok, [id, ops]} <- normalized_payload_args(payload, 2),
         {:ok, ops} <- normalized_list_values(ops),
         {:ok, op_nodes} <- normalize_rendered_list(ops, &normalize_rendered_op_node/1) do
      {:ok,
       %{
         "type" => "canvasLayer",
         "label" => "",
         "id" => rendered_expr_scalar(normalize_rendered_child(id)),
         "children" => op_nodes
       }}
    else
      _ -> :error
    end
  end

  @spec normalize_rendered_op_node(Types.runtime_value()) :: {:ok, map()} | :error
  defp normalize_rendered_op_node(%{} = value), do: normalize_rendered_ui_value(value)
  defp normalize_rendered_op_node(_value), do: :error

  @spec normalize_rendered_child(Types.runtime_value()) :: Types.runtime_value()
  defp normalize_rendered_child(%{"type" => _type} = value), do: normalize_rendered_tree(value)
  defp normalize_rendered_child(value), do: value

  @spec promote_rendered_node_args(map()) :: map()
  defp promote_rendered_node_args(%{"type" => "window", "children" => [id | rest]} = node) do
    case rendered_expr_scalar(id) do
      nil -> node
      value -> node |> Map.put("id", value) |> Map.put("children", rest)
    end
  end

  defp promote_rendered_node_args(%{"type" => "canvasLayer", "children" => [id | rest]} = node) do
    case rendered_expr_scalar(id) do
      nil -> node
      value -> node |> Map.put("id", value) |> Map.put("children", rest)
    end
  end

  defp promote_rendered_node_args(%{"type" => "text", "children" => children} = node)
       when is_list(children) and length(children) == 6 do
    values = Enum.map(children, &rendered_expr_scalar/1)

    if Enum.all?(values, &(!is_nil(&1))) do
      ["font_id", "x", "y", "w", "h", "text"]
      |> Enum.zip(values)
      |> Enum.reduce(Map.put(node, "children", []), fn {field, value}, acc ->
        put_rendered_node_arg(acc, field, value)
      end)
      |> Map.put("text_align", "center")
      |> Map.put("text_overflow", "word_wrap")
    else
      node
    end
  end

  defp promote_rendered_node_args(%{"type" => "line", "children" => [from, to, color]} = node) do
    with {:ok, {x1, y1}} <- rendered_point_child(from),
         {:ok, {x2, y2}} <- rendered_point_child(to),
         stroke when is_integer(stroke) <- rendered_scalar_color(color) do
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

  defp promote_rendered_node_args(%{"type" => "roundRect", "children" => [bounds, radius, color]} = node) do
    with {:ok, {x, y, w, h}} <- rendered_rect_child(bounds),
         radius when is_integer(radius) <- rendered_scalar_int(radius),
         fill when is_integer(fill) <- rendered_scalar_color(color) do
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

  defp promote_rendered_node_args(%{"children" => children} = node) when is_list(children) do
    fields = rendered_node_arg_fields(Map.get(node, "type"))

    if fields != [] and length(fields) == length(children) do
      values = Enum.map(children, &rendered_expr_scalar/1)

      if Enum.all?(values, &(!is_nil(&1))) do
        fields
        |> Enum.zip(values)
        |> Enum.reduce(Map.put(node, "children", []), fn {field, value}, acc ->
          put_rendered_node_arg(acc, field, value)
        end)
      else
        node
      end
    else
      node
    end
  end

  defp promote_rendered_node_args(node), do: node

  @spec put_rendered_node_arg(map(), String.t(), Types.runtime_value()) :: map()
  defp put_rendered_node_arg(node, "text", value) when is_map(node) do
    Map.put(node, "text", normalize_rendered_text(value) || "")
  end

  defp put_rendered_node_arg(node, "text_align", value) when is_map(node) do
    Map.put(node, "text_align", rendered_text_alignment(value))
  end

  defp put_rendered_node_arg(node, "text_overflow", value) when is_map(node) do
    Map.put(node, "text_overflow", rendered_text_overflow(value))
  end

  defp put_rendered_node_arg(node, field, value) when is_map(node) do
    Map.put(node, field, value)
  end

  defp rendered_text_alignment(0), do: "left"
  defp rendered_text_alignment(2), do: "right"
  defp rendered_text_alignment(value) when is_binary(value), do: value
  defp rendered_text_alignment(_), do: "center"

  defp rendered_text_overflow(1), do: "trailing_ellipsis"
  defp rendered_text_overflow(2), do: "fill"
  defp rendered_text_overflow(value) when is_binary(value), do: value
  defp rendered_text_overflow(_), do: "word_wrap"

  @spec normalize_rendered_text_field(map()) :: map()
  defp normalize_rendered_text_field(%{"text" => value} = node) do
    case normalize_rendered_text(value) do
      nil -> node
      text -> Map.put(node, "text", text)
    end
  end

  defp normalize_rendered_text_field(node), do: node

  @spec normalize_rendered_text(Types.runtime_value()) :: String.t() | nil
  defp normalize_rendered_text(value) when is_binary(value) do
    if String.trim(value) != "", do: value, else: nil
  end

  defp normalize_rendered_text(value) when is_integer(value), do: Integer.to_string(value)

  defp normalize_rendered_text(value) when is_float(value),
    do: :erlang.float_to_binary(value, [:compact])

  defp normalize_rendered_text(value) when is_list(value) do
    if List.ascii_printable?(value) do
      value
      |> List.to_string()
      |> normalize_rendered_text()
    else
      nil
    end
  end

  defp normalize_rendered_text(_value), do: nil

  @spec rendered_point_child(Types.runtime_value()) :: {:ok, {integer(), integer()}} | :error
  defp rendered_point_child(%{"x" => x, "y" => y}),
    do: {:ok, {rendered_scalar_int(x), rendered_scalar_int(y)}}

  defp rendered_point_child(%{x: x, y: y}),
    do: {:ok, {rendered_scalar_int(x), rendered_scalar_int(y)}}

  defp rendered_point_child(%{"type" => "expr", "value" => %{"x" => _} = point}),
    do: rendered_point_child(point)

  defp rendered_point_child(%{"type" => "expr"} = node) do
    case rendered_expr_scalar(node) do
      %{"x" => _, "y" => _} = point -> rendered_point_child(point)
      _ -> :error
    end
  end

  defp rendered_point_child(_), do: :error

  @spec rendered_rect_child(Types.runtime_value()) :: {:ok, {integer(), integer(), integer(), integer()}} | :error
  defp rendered_rect_child(%{"x" => x, "y" => y, "w" => w, "h" => h}),
    do: {:ok, {rendered_scalar_int(x), rendered_scalar_int(y), rendered_scalar_int(w), rendered_scalar_int(h)}}

  defp rendered_rect_child(%{x: x, y: y, w: w, h: h}),
    do: {:ok, {rendered_scalar_int(x), rendered_scalar_int(y), rendered_scalar_int(w), rendered_scalar_int(h)}}

  defp rendered_rect_child(%{"type" => "expr", "value" => %{"x" => _} = bounds}),
    do: rendered_rect_child(bounds)

  defp rendered_rect_child(%{"type" => "expr"} = node) do
    case rendered_expr_scalar(node) do
      %{"x" => _, "y" => _, "w" => _, "h" => _} = bounds -> rendered_rect_child(bounds)
      _ -> :error
    end
  end

  defp rendered_rect_child(_), do: :error

  @spec rendered_scalar_int(Types.runtime_value()) :: integer() | nil
  defp rendered_scalar_int(value) when is_integer(value), do: value
  defp rendered_scalar_int(value) when is_float(value), do: trunc(value)

  defp rendered_scalar_int(%{"type" => "expr"} = node) do
    case rendered_expr_scalar(node) do
      n when is_integer(n) -> n
      n when is_float(n) -> trunc(n)
      _ -> nil
    end
  end

  defp rendered_scalar_int(_), do: nil

  @spec rendered_scalar_color(Types.runtime_value()) :: integer() | nil
  defp rendered_scalar_color(value) when is_integer(value), do: value

  defp rendered_scalar_color(%{"type" => "expr"} = node) do
    case rendered_expr_scalar(node) do
      n when is_integer(n) -> n
      _ -> nil
    end
  end

  defp rendered_scalar_color(_), do: nil

  @spec rendered_expr_scalar(Types.runtime_value()) :: Types.runtime_value()
  defp rendered_expr_scalar(%{"type" => "expr"} = node) do
    cond do
      Map.has_key?(node, "value") -> Map.get(node, "value")
      is_binary(Map.get(node, "label")) -> Map.get(node, "label")
      true -> nil
    end
  end

  defp rendered_expr_scalar(_node), do: nil

  @spec rendered_node_arg_fields(String.t() | atom()) :: [String.t()]
  defp rendered_node_arg_fields(type) do
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

  @spec normalize_rendered_list([Types.runtime_value()], (Types.runtime_value() ->
                                                            {:ok, map()} | :error)) ::
          {:ok, [map()]} | :error
  defp normalize_rendered_list(values, fun) when is_list(values) and is_function(fun, 1) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case fun.(value) do
        {:ok, node} -> {:cont, {:ok, [node | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, nodes} -> {:ok, Enum.reverse(nodes)}
      :error -> :error
    end
  end

  @spec normalized_tagged_tuple(Types.runtime_value()) ::
          {:ok, integer(), Types.runtime_value()} | :error
  defp normalized_tagged_tuple(%{"type" => "tuple2", "children" => [tag_node, payload]}) do
    case normalized_expr_value(tag_node) do
      tag when is_integer(tag) -> {:ok, tag, payload}
      _ -> :error
    end
  end

  defp normalized_tagged_tuple(_value), do: :error

  @spec normalized_expr_value(Types.runtime_value()) :: Types.runtime_value()
  defp normalized_expr_value(%{"type" => "expr"} = node), do: Map.get(node, "value")
  defp normalized_expr_value(_node), do: nil

  @spec normalized_list_values(Types.runtime_value()) :: {:ok, [Types.runtime_value()]} | :error
  defp normalized_list_values(%{"type" => "List", "children" => children}) when is_list(children),
    do: {:ok, children}

  defp normalized_list_values(values) when is_list(values), do: {:ok, values}
  defp normalized_list_values(_values), do: :error

  @spec normalized_payload_args(Types.runtime_value(), pos_integer()) ::
          {:ok, [Types.runtime_value()]} | :error
  defp normalized_payload_args(payload, arity) when is_integer(arity) and arity > 1 do
    flatten_normalized_payload(payload, arity, [])
  end

  @spec flatten_normalized_payload(Types.runtime_value(), non_neg_integer(), [
          Types.runtime_value()
        ]) ::
          {:ok, [Types.runtime_value()]} | :error
  defp flatten_normalized_payload(value, 1, acc), do: {:ok, Enum.reverse([value | acc])}

  defp flatten_normalized_payload(
         %{"type" => "tuple2", "children" => [left, right]},
         remaining,
         acc
       )
       when remaining > 1 do
    flatten_normalized_payload(right, remaining - 1, [left | acc])
  end

  defp flatten_normalized_payload(_value, _remaining, _acc), do: :error

  @spec runtime_model(map()) :: map()
  defp runtime_model(%{} = runtime) do
    case Map.get(runtime, :model) || Map.get(runtime, "model") do
      model when is_map(model) -> model
      _ -> %{}
    end
  end

  @spec parser_view_tree(map()) :: map() | nil
  defp parser_view_tree(%{} = model) do
    case RuntimeArtifacts.introspect(model) do
      ei when is_map(ei) ->
        tree = Map.get(ei, "view_tree") || Map.get(ei, :view_tree)
        if is_map(tree), do: tree, else: nil

      _ ->
        nil
    end
  end

  @spec rendered_view_preview(map() | nil) :: String.t()
  def rendered_view_preview(nil), do: "(no snapshot)"

  def rendered_view_preview(runtime) when is_map(runtime) do
    tree = Map.get(runtime, :view_tree) || Map.get(runtime, "view_tree")
    model = preview_runtime_model(runtime)
    runtime_ops = runtime_view_output_lines(runtime)

    case tree do
      %{} = node ->
        tree_text = format_rendered_node(node, 0, model, nil) |> String.trim_trailing()
        Util.join_preview_sections(runtime_ops, tree_text)

      _ ->
        "(no rendered view in snapshot)"
    end
  end

  def rendered_view_preview(_), do: "(no snapshot)"

  @spec format_rendered_node(Types.rendered_node(), non_neg_integer(), map(), String.t() | nil) ::
          String.t()
  defp format_rendered_node(node, depth, model, arg_name)
       when is_map(node) and is_integer(depth) and is_map(model) do
    indent = String.duplicate("  ", max(depth, 0))
    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "node")

    children = Map.get(node, "children") || Map.get(node, :children) || []

    child_text =
      children
      |> Enum.filter(&is_map/1)
      |> rendered_child_rows(node)
      |> Enum.map_join("", fn {child, child_arg_name} ->
        format_rendered_node(child, depth + 1, model, child_arg_name)
      end)

    if hidden_rendered_node_type?(type) do
      child_text
    else
      summary = rendered_node_summary(node, model, arg_name)

      "#{indent}- #{summary}\n#{child_text}"
    end
  end

  defp format_rendered_node(_node, _depth, _model, _arg_name), do: ""

  @spec hidden_rendered_node_type?(String.t()) :: boolean()
  defp hidden_rendered_node_type?(type) when is_binary(type) do
    type in ["debuggerRenderStep", "elmcRuntimeStep"]
  end

  @spec render_suffix(String.t() | integer() | nil) :: String.t()
  defp render_suffix(""), do: ""
  defp render_suffix(nil), do: ""
  defp render_suffix(value), do: "[#{value}]"

  @spec rendered_node_summary(map(), map(), String.t() | nil) :: String.t()
  def rendered_node_summary(node, model, arg_name \\ nil)

  def rendered_node_summary(node, model, arg_name) when is_map(node) and is_map(model) do
    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "node")
    label = Map.get(node, "label") || Map.get(node, :label) || ""
    text = Map.get(node, "text") || Map.get(node, :text) || ""
    value_hint = rendered_value_hint(node, model)
    value = rendered_node_value(node, value_hint)
    arg_name = rendered_arg_name(arg_name)
    detail = rendered_node_detail_suffix(node)

    cond do
      arg_name != nil and value != "" ->
        [value, render_suffix(arg_name), detail]
        |> Enum.reject(&(&1 == ""))
        |> Enum.join(" ")

      arg_name != nil ->
        [type, render_suffix(arg_name), detail]
        |> Enum.reject(&(&1 == ""))
        |> Enum.join(" ")

      true ->
        [type, render_suffix(label), render_suffix(text), render_suffix(value_hint), detail]
        |> Enum.reject(&(&1 == ""))
        |> Enum.uniq()
        |> Enum.join(" ")
    end
  end

  def rendered_node_summary(_node, _model, _arg_name), do: "node"

  @spec rendered_node_detail_suffix(map()) :: String.t()
  defp rendered_node_detail_suffix(node) when is_map(node) do
    fields =
      node
      |> rendered_detail_fields()
      |> Enum.flat_map(fn field ->
        case map_scalar_detail(node, field) do
          "" -> []
          value -> ["#{field}=#{rendered_detail_value(node, field, value)}"]
        end
      end)

    child_count = rendered_visible_child_count(node)
    count_suffix = rendered_child_count_suffix(node, child_count)

    (fields ++ List.wrap(count_suffix))
    |> Enum.reject(&(&1 in ["", nil]))
    |> case do
      [] -> ""
      parts -> "(" <> Enum.join(parts, ", ") <> ")"
    end
  end

  @spec rendered_detail_value(map(), String.t(), String.t()) :: String.t()
  defp rendered_detail_value(node, field, value)
       when is_map(node) and is_binary(field) and is_binary(value) do
    if rendered_color_field?(node, field) do
      color_value = scalar_map_value(node, field)

      case rendered_color_label(color_value) do
        "" -> value
        label -> "#{value} #{label}"
      end
    else
      value
    end
  end

  @spec rendered_color_field?(map(), String.t()) :: boolean()
  defp rendered_color_field?(node, field) when is_map(node) and is_binary(field) do
    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "")

    field in rendered_node_color_fields(type)
  end

  @spec rendered_node_color_fields(String.t()) :: [String.t()]
  defp rendered_node_color_fields(type) do
    case type do
      "clear" -> ["color"]
      "pixel" -> ["color"]
      "line" -> ["color"]
      "rect" -> ["color"]
      "fillRect" -> ["fill"]
      "circle" -> ["color"]
      "fillCircle" -> ["color"]
      "roundRect" -> ["fill"]
      _ -> []
    end
  end

  @spec rendered_color_label(integer()) :: String.t()
  defp rendered_color_label(value) when is_integer(value) and value >= 0 and value <= 255 do
    name = pebble_color_name(value)
    hex = pebble_color_hex(value)

    case name do
      "" -> "(#{hex})"
      _ -> "(#{name}, #{hex})"
    end
  end

  defp rendered_color_label(_value), do: ""

  @spec pebble_color_name(integer()) :: String.t()
  defp pebble_color_name(value) do
    case value do
      0x00 -> "clearColor"
      0xC0 -> "black"
      0xC1 -> "oxfordBlue"
      0xC2 -> "dukeBlue"
      0xC3 -> "blue"
      0xC4 -> "darkGreen"
      0xC5 -> "midnightGreen"
      0xC6 -> "cobaltBlue"
      0xC7 -> "blueMoon"
      0xC8 -> "islamicGreen"
      0xC9 -> "jaegerGreen"
      0xCA -> "tiffanyBlue"
      0xCB -> "vividCerulean"
      0xCC -> "green"
      0xCD -> "malachite"
      0xCE -> "mediumSpringGreen"
      0xCF -> "cyan"
      0xD0 -> "bulgarianRose"
      0xD1 -> "imperialPurple"
      0xD2 -> "indigo"
      0xD3 -> "electricUltramarine"
      0xD4 -> "armyGreen"
      0xD5 -> "darkGray"
      0xD6 -> "liberty"
      0xD7 -> "veryLightBlue"
      0xD8 -> "kellyGreen"
      0xD9 -> "mayGreen"
      0xDA -> "cadetBlue"
      0xDB -> "pictonBlue"
      0xDC -> "brightGreen"
      0xDD -> "screaminGreen"
      0xDE -> "mediumAquamarine"
      0xDF -> "electricBlue"
      0xE0 -> "darkCandyAppleRed"
      0xE1 -> "jazzberryJam"
      0xE2 -> "purple"
      0xE3 -> "vividViolet"
      0xE4 -> "windsorTan"
      0xE5 -> "roseVale"
      0xE6 -> "purpureus"
      0xE7 -> "lavenderIndigo"
      0xE8 -> "limerick"
      0xE9 -> "brass"
      0xEA -> "lightGray"
      0xEB -> "babyBlueEyes"
      0xEC -> "springBud"
      0xED -> "inchworm"
      0xEE -> "mintGreen"
      0xEF -> "celeste"
      0xF0 -> "red"
      0xF1 -> "folly"
      0xF2 -> "fashionMagenta"
      0xF3 -> "magenta"
      0xF4 -> "orange"
      0xF5 -> "sunsetOrange"
      0xF6 -> "brilliantRose"
      0xF7 -> "shockingPink"
      0xF8 -> "chromeYellow"
      0xF9 -> "rajah"
      0xFA -> "melon"
      0xFB -> "richBrilliantLavender"
      0xFC -> "yellow"
      0xFD -> "icterine"
      0xFE -> "pastelYellow"
      0xFF -> "white"
      _ -> ""
    end
  end

  @spec pebble_color_hex(integer()) :: String.t()
  defp pebble_color_hex(value) when is_integer(value) do
    alpha = value |> Bitwise.bsr(6) |> Bitwise.band(0x03)
    red = value |> Bitwise.bsr(4) |> Bitwise.band(0x03)
    green = value |> Bitwise.bsr(2) |> Bitwise.band(0x03)
    blue = Bitwise.band(value, 0x03)

    [red, green, blue, alpha]
    |> Enum.map(&color_2bit_to_hex/1)
    |> Enum.join()
    |> then(&"##{&1}")
  end

  @spec color_2bit_to_hex(integer()) :: String.t()
  defp color_2bit_to_hex(value) when is_integer(value) do
    value
    |> max(0)
    |> min(3)
    |> Kernel.*(85)
    |> Integer.to_string(16)
    |> String.pad_leading(2, "0")
  end

  @spec rendered_detail_fields(map()) :: [String.t()]
  defp rendered_detail_fields(node) when is_map(node) do
    type = Map.get(node, "type") || Map.get(node, :type)
    base = rendered_node_arg_fields(type)

    if Map.has_key?(node, "id") or Map.has_key?(node, :id) do
      ["id" | base]
    else
      base
    end
  end

  @spec map_scalar_detail(map(), String.t()) :: String.t()
  defp map_scalar_detail(node, field) when is_map(node) and is_binary(field) do
    node
    |> scalar_map_value(field)
    |> rendered_scalar_value()
  end

  @spec scalar_map_value(map(), String.t()) :: Types.runtime_value()
  defp scalar_map_value(node, field) when is_map(node) and is_binary(field) do
    cond do
      Map.has_key?(node, field) ->
        Map.get(node, field)

      true ->
        node
        |> Enum.find_value(fn
          {key, value} when is_atom(key) ->
            if Atom.to_string(key) == field, do: {:ok, value}, else: nil

          _ ->
            nil
        end)
        |> case do
          {:ok, value} -> value
          _ -> nil
        end
    end
  end

  @spec rendered_visible_child_count(map()) :: non_neg_integer()
  defp rendered_visible_child_count(node) when is_map(node) do
    node
    |> Map.get("children", Map.get(node, :children, []))
    |> Enum.filter(fn
      %{} = child ->
        type = to_string(Map.get(child, "type") || Map.get(child, :type) || "")
        not hidden_rendered_node_type?(type)

      _ ->
        false
    end)
    |> length()
  end

  @spec rendered_child_count_suffix(map(), non_neg_integer()) :: String.t() | nil
  defp rendered_child_count_suffix(node, child_count) when is_map(node) and child_count > 0 do
    case to_string(Map.get(node, "type") || Map.get(node, :type) || "") do
      "windowStack" -> "#{child_count} #{pluralize("window", child_count)}"
      "window" -> "#{child_count} #{pluralize("layer", child_count)}"
      "canvasLayer" -> "#{child_count} #{pluralize("op", child_count)}"
      "group" -> "#{child_count} #{pluralize("op", child_count)}"
      _ -> nil
    end
  end

  defp rendered_child_count_suffix(_node, _child_count), do: nil

  @spec pluralize(String.t(), non_neg_integer()) :: String.t()
  defp pluralize(noun, 1), do: noun
  defp pluralize(noun, _count), do: noun <> "s"

  @spec rendered_child_rows([map()], map()) :: [{map(), String.t() | nil}]
  defp rendered_child_rows(children, parent) when is_list(children) and is_map(parent) do
    arg_names = rendered_node_arg_names(parent, length(children))

    children
    |> Enum.with_index()
    |> Enum.map(fn {child, index} ->
      {child, Enum.at(arg_names, index)}
    end)
  end

  @spec rendered_arg_name(map()) :: String.t() | nil
  defp rendered_arg_name(name) when is_binary(name) do
    trimmed = String.trim(name)
    if trimmed == "", do: nil, else: trimmed
  end

  defp rendered_arg_name(_name), do: nil

  @spec rendered_node_arg_names(map(), non_neg_integer()) :: [String.t()]
  defp rendered_node_arg_names(parent, child_count)
       when is_map(parent) and is_integer(child_count) do
    explicit = Map.get(parent, "arg_names") || Map.get(parent, :arg_names) || []

    if explicit != [] do
      explicit
    else
      []
    end
  end

  @spec rendered_node_value(map(), String.t()) :: String.t()
  defp rendered_node_value(node, value_hint) when is_map(node) do
    cond do
      value_hint not in [nil, ""] ->
        to_string(value_hint)

      Map.has_key?(node, "value") ->
        rendered_scalar_value(Map.get(node, "value"))

      Map.has_key?(node, :value) ->
        rendered_scalar_value(Map.get(node, :value))

      true ->
        rendered_label_value(node)
    end
  end

  @spec rendered_label_value(map()) :: String.t()
  defp rendered_label_value(node) when is_map(node) do
    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "")
    label = Map.get(node, "label") || Map.get(node, :label)

    if type in ["expr", "var"] do
      rendered_scalar_value(label)
    else
      ""
    end
  end

  @spec rendered_scalar_value(Types.runtime_value()) :: String.t()
  defp rendered_scalar_value(value) when is_integer(value), do: Integer.to_string(value)

  defp rendered_scalar_value(value) when is_float(value),
    do: :erlang.float_to_binary(value, decimals: 2)

  defp rendered_scalar_value(value) when is_binary(value), do: value
  defp rendered_scalar_value(value) when is_boolean(value), do: to_string(value)
  defp rendered_scalar_value(_value), do: ""

  @spec preview_runtime_model(map()) :: map()
  defp preview_runtime_model(runtime) when is_map(runtime) do
    nested = Map.get(runtime, :model) || Map.get(runtime, "model")

    cond do
      is_map(nested) ->
        Map.get(nested, "runtime_model") || Map.get(nested, :runtime_model) || nested

      is_map(Map.get(runtime, "runtime_model")) ->
        Map.get(runtime, "runtime_model")

      is_map(Map.get(runtime, :runtime_model)) ->
        Map.get(runtime, :runtime_model)

      true ->
        runtime
    end
  end

  @spec rendered_value_hint(Types.runtime_value(), map()) :: String.t() | nil
  defp rendered_value_hint(node, model) when is_map(node) and is_map(model) do
    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "")
    label = to_string(Map.get(node, "label") || Map.get(node, :label) || "")
    op = to_string(Map.get(node, "op") || Map.get(node, :op) || "")
    preview_model = preview_runtime_model(model)

    cond do
      type == "field" ->
        node
        |> rendered_node_children()
        |> List.first()
        |> rendered_value_hint(preview_model) ||
          (node
           |> rendered_node_children()
           |> List.first()
           |> evaluated_rendered_scalar_hint(preview_model))

      type == "call" and label == "__idiv__" ->
        evaluate_rendered_binop_hint(node, preview_model, div: 2)

      type == "call" ->
        evaluated_rendered_scalar_hint(node, model)

      type == "expr" and op in ["tuple_first_expr", "tuple_second_expr"] ->
        evaluated_rendered_scalar_hint(node, model)

      type == "expr" and op == "field_access" and String.starts_with?(label, "model.") ->
        evaluated_rendered_scalar_hint(node, model) ||
          label
          |> String.replace_prefix("model.", "")
          |> then(&Map.get(preview_model, &1))
          |> rendered_int_hint()

      type == "var" ->
        evaluated_rendered_scalar_hint(node, model) || rendered_int_hint(Map.get(model, label))

      true ->
        nil
    end
  end

  defp rendered_value_hint(_node, _model), do: nil

  @spec evaluate_rendered_binop_hint(map(), map(), keyword()) :: String.t() | nil
  defp evaluate_rendered_binop_hint(node, model, div: _divisor) when is_map(node) and is_map(model) do
    case rendered_node_children(node) do
      [left, right | _] ->
        with left_int when is_integer(left_int) <- rendered_expr_int(left, model),
             right_int when is_integer(right_int) <- rendered_expr_int(right, model),
             true <- right_int != 0 do
          Integer.to_string(div(left_int, right_int))
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp evaluate_rendered_binop_hint(_node, _model, _op), do: nil

  @spec rendered_expr_int(map(), map()) :: integer() | nil
  defp rendered_expr_int(node, model) when is_map(node) and is_map(model) do
    op = to_string(Map.get(node, "op") || Map.get(node, :op) || "")
    label = to_string(Map.get(node, "label") || Map.get(node, :label) || "")

    cond do
      is_integer(Map.get(node, "value")) ->
        Map.get(node, "value")

      is_float(Map.get(node, "value")) ->
        trunc(Map.get(node, "value"))

      op == "field_access" and String.starts_with?(label, "model.") ->
        label
        |> String.replace_prefix("model.", "")
        |> then(&Map.get(model, &1))
        |> case do
          n when is_integer(n) -> n
          n when is_float(n) -> trunc(n)
          _ -> nil
        end

      true ->
        case rendered_expr_scalar(node) do
          n when is_integer(n) -> n
          n when is_float(n) -> trunc(n)
          _ -> nil
        end
    end
  end

  defp rendered_expr_int(_node, _model), do: nil

  @spec rendered_node_children(map()) :: [map()]
  defp rendered_node_children(node) when is_map(node) do
    case Map.get(node, "children") || Map.get(node, :children) do
      children when is_list(children) -> Enum.filter(children, &is_map/1)
      _ -> []
    end
  end

  @spec evaluated_rendered_scalar_hint(Types.runtime_value(), map()) :: String.t() | nil
  defp evaluated_rendered_scalar_hint(node, _model) when is_map(node) do
    (Map.get(node, "value") ||
       Map.get(node, :value) ||
       Map.get(node, "evaluated_value") ||
       Map.get(node, :evaluated_value))
    |> rendered_scalar_hint()
  end

  defp evaluated_rendered_scalar_hint(_node, _model), do: nil

  @spec rendered_scalar_hint(Types.runtime_value()) :: String.t() | nil
  defp rendered_scalar_hint(value) when is_integer(value), do: Integer.to_string(value)

  defp rendered_scalar_hint(value) when is_float(value),
    do: :erlang.float_to_binary(value, [:compact])

  defp rendered_scalar_hint(value) when is_binary(value), do: value
  defp rendered_scalar_hint(value) when is_boolean(value), do: to_string(value)
  defp rendered_scalar_hint(_value), do: nil

  @spec rendered_int_hint(Types.runtime_value()) :: String.t() | nil
  defp rendered_int_hint(value) when is_integer(value), do: Integer.to_string(value)
  defp rendered_int_hint(value) when is_float(value), do: Integer.to_string(trunc(value))
  defp rendered_int_hint(_), do: nil

  @spec runtime_view_output_lines(map()) :: String.t()
  defp runtime_view_output_lines(runtime) when is_map(runtime) do
    model = Map.get(runtime, :model) || Map.get(runtime, "model") || %{}
    ops = Map.get(model, "runtime_view_output") || Map.get(model, :runtime_view_output) || []

    ops
    |> List.wrap()
    |> Enum.filter(&is_map/1)
    |> Enum.map(&runtime_op_line/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> ""
      lines -> Enum.join(lines, "\n")
    end
  end

  @spec runtime_op_line(map()) :: String.t()
  defp runtime_op_line(op) when is_map(op) do
    kind = to_string(Map.get(op, "kind") || Map.get(op, :kind) || "")

    case kind do
      "clear" ->
        "- clear [#{map_integer_value(op, "color", 0)}]"

      "round_rect" ->
        "- roundRect [x=#{map_integer_value(op, "x", 0)}, y=#{map_integer_value(op, "y", 0)}, w=#{map_integer_value(op, "w", 0)}, h=#{map_integer_value(op, "h", 0)}, r=#{map_integer_value(op, "radius", 0)}, fill=#{map_integer_value(op, "fill", 0)}]"

      "rect" ->
        "- rect [x=#{map_integer_value(op, "x", 0)}, y=#{map_integer_value(op, "y", 0)}, w=#{map_integer_value(op, "w", 0)}, h=#{map_integer_value(op, "h", 0)}, fill=#{map_integer_value(op, "fill", 0)}]"

      "line" ->
        "- line [#{map_integer_value(op, "x1", 0)}, #{map_integer_value(op, "y1", 0)} -> #{map_integer_value(op, "x2", 0)}, #{map_integer_value(op, "y2", 0)}]"

      "pixel" ->
        "- pixel [#{map_integer_value(op, "x", 0)}, #{map_integer_value(op, "y", 0)}, c=#{map_integer_value(op, "color", 0)}]"

      "text_int" ->
        text = to_string(Map.get(op, "text") || Map.get(op, :text) || "")

        "- textInt [x=#{map_integer_value(op, "x", 0)}, y=#{map_integer_value(op, "y", 0)}, #{text}]"

      "text_label" ->
        text = to_string(Map.get(op, "text") || Map.get(op, :text) || "")

        "- textLabel [x=#{map_integer_value(op, "x", 0)}, y=#{map_integer_value(op, "y", 0)}, #{text}]"

      "unresolved" ->
        node_type = to_string(Map.get(op, "node_type") || Map.get(op, :node_type) || "node")
        provided = map_integer_value(op, "provided_int_count", 0)
        required = map_integer_value(op, "required_int_count", 0)
        label = to_string(Map.get(op, "label") || Map.get(op, :label) || "")
        "- unresolved [#{node_type}, ints=#{provided}/#{required}, #{label}]"

      _ ->
        ""
    end
  end

  defp runtime_op_line(_op), do: ""

  @spec map_integer_value(map(), String.t() | atom(), integer()) :: integer()
  defp map_integer_value(map, key, default)
       when is_map(map) and is_binary(key) and is_integer(default) do
    atom_key =
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
        "font_id" -> :font_id
        "bitmap_id" -> :bitmap_id
        "vector_id" -> :vector_id
        "src_w" -> :src_w
        "src_h" -> :src_h
        "angle" -> :angle
        "center_x" -> :center_x
        "center_y" -> :center_y
        "start_angle" -> :start_angle
        "end_angle" -> :end_angle
        _ -> nil
      end

    value = Map.get(map, key) || Map.get(map, atom_key)

    cond do
      is_integer(value) ->
        value

      is_float(value) ->
        trunc(value)

      is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} -> parsed
          _ -> default
        end

      true ->
        default
    end
  end
end
