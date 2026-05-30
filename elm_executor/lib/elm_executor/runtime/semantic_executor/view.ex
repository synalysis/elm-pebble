defmodule ElmExecutor.Runtime.SemanticExecutor.View do
  @moduledoc false
  @dialyzer :no_match

  alias ElmExecutor.Runtime.SemanticExecutor.Execution
  alias ElmExecutor.Runtime.SemanticExecutor.ViewTreeEval

  alias ElmEx.CoreIR
  alias ElmEx.Frontend.GeneratedParser
  alias ElmEx.Frontend.Project
  alias ElmEx.IR.Lowerer
  alias ElmExecutor.Runtime.CoreIREvaluator
  alias ElmExecutor.Runtime.CoreIREvaluator.Types, as: EvalTypes
  alias ElmExecutor.Runtime.SemanticExecutor.Types, as: SemTypes
  @doc """
  Derives drawable preview rows from a parser-shaped view tree and runtime model.

  Used when full Core IR view evaluation is unavailable but the introspected view
  tree still contains render-operation structure.
  """
  @spec derive_view_output_preview(map(), map(), map()) :: [map()]
  def derive_view_output_preview(view_tree, runtime_model, eval_context \\ %{})

  def derive_view_output_preview(view_tree, runtime_model, eval_context)
      when is_map(view_tree) and is_map(runtime_model) and is_map(eval_context) do
    eval_context = Map.put(eval_context, :runtime_model, runtime_model)

    view_tree
    |> derive_view_output(runtime_model, eval_context)
    |> Enum.map(&stringify_view_output_row/1)
  end

  def derive_view_output_preview(_view_tree, _runtime_model, _eval_context), do: []

  @doc """
  Evaluates `view` through Core IR and derives drawable preview rows from the result.

  Returns empty `view_output` when evaluation fails or produces no drawable ops.
  `eval_context` must include Core IR function indexes (see IDE `RuntimeArtifacts.core_ir_eval_context/1`).
  """
  @spec derive_view_output_for_runtime_model(map(), map()) :: %{
          view_output: [map()],
          view_tree: map()
        }
  def derive_view_output_for_runtime_model(runtime_model, eval_context)
      when is_map(runtime_model) and is_map(eval_context) do
    eval_context = Map.put(eval_context, :runtime_model, runtime_model)
    evaluated_tree = evaluate_runtime_view_tree(eval_context, runtime_model)

    view_output =
      if drawable_view_tree?(evaluated_tree) do
        evaluated_tree
        |> derive_view_output(runtime_model, eval_context)
        |> Enum.map(&stringify_view_output_row/1)
        |> Enum.reject(fn row -> Map.get(row, "kind") == "unresolved" end)
      else
        []
      end

    %{view_output: view_output, view_tree: evaluated_tree}
  end

  def derive_view_output_for_runtime_model(_runtime_model, _eval_context),
    do: %{view_output: [], view_tree: %{}}

  @spec drawable_view_tree?(map()) :: boolean()
  def drawable_view_tree?(tree) when is_map(tree) do
    type = to_string(Map.get(tree, "type") || Map.get(tree, :type) || "")

    type in drawable_view_tree_types() or
      Enum.any?(Map.get(tree, "children") || Map.get(tree, :children) || [], &drawable_view_tree?/1)
  end

  def drawable_view_tree?(_tree), do: false

  @spec drawable_view_tree_types() :: [String.t()]
  def drawable_view_tree_types do
    [
      "clear",
      "roundRect",
      "fillRect",
      "rect",
      "text",
      "line",
      "circle",
      "fillCircle",
      "drawVectorAt",
      "drawVectorSequenceAt",
      "drawBitmapSequenceAt",
      "bitmapInRect",
      "rotatedBitmap",
      "path",
      "windowStack",
      "window",
      "canvasLayer",
      "root"
    ]
  end

  @spec stringify_view_output_row(map()) :: map()
  defp stringify_view_output_row(row) when is_map(row) do
    Map.new(row, fn {key, value} -> {to_string(key), value} end)
  end
  @spec derive_view_tree(map(), map(), map(), String.t(), String.t() | nil, atom() | nil, map()) :: map()
  def derive_view_tree(
         current_view_tree,
         introspect,
         runtime_model,
         source_root,
         message,
         op,
         eval_context
       ) do
    evaluated_runtime_tree = evaluate_runtime_view_tree(eval_context, runtime_model)

    base =
      cond do
        is_map(evaluated_runtime_tree) and map_size(evaluated_runtime_tree) > 0 ->
          evaluated_runtime_tree

        not (is_binary(message) and message != "") and is_map(Execution.map_value(introspect, :view_tree)) ->
          Execution.map_value(introspect, :view_tree)

        is_map(current_view_tree) and map_size(current_view_tree) > 0 ->
          current_view_tree

        is_map(Execution.map_value(introspect, :view_tree)) ->
          Execution.map_value(introspect, :view_tree)

        true ->
          %{"type" => "root", "children" => []}
      end
      |> normalize_runtime_text_fields()

    if is_binary(message) and is_atom(op) do
      children =
        case Map.get(base, "children") || Map.get(base, :children) do
          xs when is_list(xs) -> xs
          _ -> []
        end

      marker = %{
        "type" => "elmcRuntimeStep",
        "label" => "#{source_root}:#{message}",
        "op" => Atom.to_string(op),
        "model_entries" => map_size(runtime_model),
        "children" => []
      }

      base
      |> Map.put("children", [marker | children] |> Enum.take(12))
      |> Map.put("last_runtime_step_message", message)
      |> Map.put("last_runtime_step_op", Atom.to_string(op))
    else
      base
    end
  end

  @spec evaluate_runtime_view_tree(map(), map()) :: map()
  def evaluate_runtime_view_tree(eval_context, runtime_model)
       when is_map(eval_context) and is_map(runtime_model) do
    entry_module = Execution.entry_module_name(eval_context)
    expr = %{"op" => :qualified_call, "target" => "#{entry_module}.view", "args" => [runtime_model]}

    case CoreIREvaluator.evaluate(expr, %{"model" => runtime_model}, eval_context) do
      {:ok, value} ->
        normalize_runtime_view_tree(value, eval_context)

      _ ->
        %{}
    end
  end

  def evaluate_runtime_view_tree(_eval_context, _runtime_model), do: %{}

  @spec normalize_runtime_view_tree(EvalTypes.runtime_value(), map()) :: map()
  defp normalize_runtime_view_tree(value, eval_context \\ %{}) do
    case normalize_pebble_ui_value(value, eval_context) do
      {:ok, node} -> node
      :error -> normalize_runtime_view_tree_fallback(value)
    end
  end

  @spec normalize_runtime_view_tree_fallback(EvalTypes.runtime_value()) :: map()
  defp normalize_runtime_view_tree_fallback(%{} = value) do
    type = value["type"] || value[:type]
    children = value["children"] || value[:children]

    cond do
      is_binary(type) and is_list(children) ->
        node = %{
          "type" => type,
          "label" => to_string(value["label"] || value[:label] || ""),
          "children" => Enum.map(children, &normalize_runtime_view_tree/1)
        }

        node =
          if Map.has_key?(value, "value"), do: Map.put(node, "value", value["value"]), else: node

        node =
          if Map.has_key?(value, :value), do: Map.put(node, "value", value[:value]), else: node

        node =
          if Map.has_key?(value, "op"),
            do: Map.put(node, "op", to_string(value["op"])),
            else: node

        node =
          if Map.has_key?(value, :op), do: Map.put(node, "op", to_string(value[:op])), else: node

        node =
          if Map.has_key?(value, "text"),
            do: Map.put(node, "text", to_string(value["text"])),
            else: node

        node =
          if Map.has_key?(value, :text),
            do: Map.put(node, "text", to_string(value[:text])),
            else: node

        node =
          cond do
            is_map(Map.get(value, "style")) ->
              Map.put(node, "style", Map.get(value, "style"))

            is_map(Map.get(value, :style)) ->
              Map.put(node, "style", Map.get(value, :style))

            true ->
              node
          end

        promote_runtime_node_args(node)

      Map.has_key?(value, "ctor") ->
        ctor = to_string(value["ctor"] || "")
        args = value["args"] || []

        %{
          "type" => ctor,
          "label" => "",
          "children" => Enum.map(List.wrap(args), &normalize_runtime_view_tree/1)
        }

      true ->
        %{"type" => "record", "label" => "", "children" => []}
    end
  end

  defp normalize_runtime_view_tree_fallback(list) when is_list(list) do
    %{
      "type" => "List",
      "label" => "[#{length(list)}]",
      "children" => Enum.map(list, &normalize_runtime_view_tree/1)
    }
  end

  defp normalize_runtime_view_tree_fallback({left, right}) do
    %{
      "type" => "tuple2",
      "label" => "",
      "children" => [normalize_runtime_view_tree(left), normalize_runtime_view_tree(right)]
    }
  end

  defp normalize_runtime_view_tree_fallback(value)
       when is_integer(value) or is_float(value) or is_boolean(value) or is_binary(value) do
    %{"type" => "expr", "label" => to_string(value), "value" => value, "children" => []}
  end

  defp normalize_runtime_view_tree_fallback(_),
    do: %{"type" => "unknown", "label" => "", "children" => []}

  @spec normalize_runtime_text_fields(EvalTypes.runtime_value()) :: EvalTypes.runtime_value()
  defp normalize_runtime_text_fields(%{} = node) do
    node
    |> normalize_runtime_text_field("text")
    |> normalize_runtime_text_field(:text)
    |> normalize_runtime_children_text_fields()
  end

  defp normalize_runtime_text_fields(values) when is_list(values),
    do: Enum.map(values, &normalize_runtime_text_fields/1)

  defp normalize_runtime_text_fields(value), do: value

  @spec normalize_runtime_text_field(map(), String.t() | atom()) :: map()
  defp normalize_runtime_text_field(node, key) when is_map(node) do
    if Map.has_key?(node, key) do
      case ViewTreeEval.normalize_text_value(Map.get(node, key)) do
        nil -> node
        text -> Map.put(node, key, text)
      end
    else
      node
    end
  end

  @spec normalize_runtime_children_text_fields(map()) :: map()
  defp normalize_runtime_children_text_fields(node) when is_map(node) do
    cond do
      is_list(Map.get(node, "children")) ->
        Map.update!(node, "children", &normalize_runtime_text_fields/1)

      is_list(Map.get(node, :children)) ->
        Map.update!(node, :children, &normalize_runtime_text_fields/1)

      true ->
        node
    end
  end

  @spec promote_runtime_node_args(map()) :: map()
  defp promote_runtime_node_args(%{"type" => "window", "children" => [id | rest]} = node) do
    case runtime_expr_scalar(id) do
      nil -> node
      value -> node |> Map.put("id", value) |> Map.put("children", rest)
    end
  end

  defp promote_runtime_node_args(%{"type" => "canvasLayer", "children" => [id | rest]} = node) do
    case runtime_expr_scalar(id) do
      nil -> node
      value -> node |> Map.put("id", value) |> Map.put("children", rest)
    end
  end

  defp promote_runtime_node_args(%{"type" => "text", "children" => children} = node)
       when is_list(children) and length(children) == 6 do
    values = Enum.map(children, &runtime_expr_scalar/1)

    if Enum.all?(values, &(!is_nil(&1))) do
      ["font_id", "x", "y", "w", "h", "text"]
      |> Enum.zip(values)
      |> Enum.reduce(Map.put(node, "children", []), fn {field, value}, acc ->
        put_runtime_node_arg(acc, field, value)
      end)
      |> Map.put("text_align", "center")
      |> Map.put("text_overflow", "word_wrap")
    else
      node
    end
  end

  defp promote_runtime_node_args(%{"children" => children} = node) when is_list(children) do
    type = Map.get(node, "type")
    fields = runtime_node_arg_fields(type)

    if fields != [] and length(fields) == length(children) do
      values = Enum.map(children, &runtime_expr_scalar/1)

      if Enum.all?(values, &(!is_nil(&1))) do
        fields
        |> Enum.zip(values)
        |> Enum.reduce(Map.put(node, "children", []), fn {field, value}, acc ->
          put_runtime_node_arg(acc, field, value)
        end)
      else
        node
      end
    else
      node
    end
  end

  defp promote_runtime_node_args(node), do: node

  @spec put_runtime_node_arg(map(), String.t(), EvalTypes.runtime_value()) :: map()
  defp put_runtime_node_arg(node, "text", value) when is_map(node) do
    Map.put(node, "text", ViewTreeEval.normalize_text_value(value) || "")
  end

  defp put_runtime_node_arg(node, "text_align", value) when is_map(node) do
    Map.put(node, "text_align", text_alignment_name(value))
  end

  defp put_runtime_node_arg(node, "text_overflow", value) when is_map(node) do
    Map.put(node, "text_overflow", text_overflow_name(value))
  end

  defp put_runtime_node_arg(node, field, value) when is_map(node) do
    Map.put(node, field, value)
  end

  @spec runtime_expr_scalar(EvalTypes.runtime_value()) :: EvalTypes.runtime_value()
  defp runtime_expr_scalar(%{"type" => "expr"} = node) do
    cond do
      Map.has_key?(node, "value") -> Map.get(node, "value")
      is_binary(Map.get(node, "label")) -> Map.get(node, "label")
      true -> nil
    end
  end

  defp runtime_expr_scalar(%{type: "expr"} = node) do
    cond do
      Map.has_key?(node, :value) -> Map.get(node, :value)
      is_binary(Map.get(node, :label)) -> Map.get(node, :label)
      true -> nil
    end
  end

  defp runtime_expr_scalar(_node), do: nil

  @spec runtime_node_arg_fields(String.t() | atom()) :: [String.t()]
  defp runtime_node_arg_fields(type) do
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
      "vectorAt" -> ["vector_id", "x", "y"]
      "drawVectorSequenceAt" -> ["vector_id", "x", "y"]
      "vectorSequenceAt" -> ["vector_id", "x", "y"]
      "drawBitmapSequenceAt" -> ["animation_id", "x", "y"]
      "bitmapSequenceAt" -> ["animation_id", "x", "y"]
      "textInt" -> ["font_id", "x", "y", "value"]
      "textLabel" -> ["font_id", "x", "y", "text"]
      "text" -> ["font_id", "x", "y", "w", "h", "text_align", "text_overflow", "text"]
      _ -> []
    end
  end

  @spec normalize_pebble_ui_value(EvalTypes.runtime_value(), map()) :: {:ok, map()} | :error
  defp normalize_pebble_ui_value(%{"type" => type, "children" => children} = value, _eval_context)
       when is_binary(type) and is_list(children) and type not in ["tuple2", "List"] do
    {:ok, normalize_runtime_view_tree_fallback(value)}
  end

  defp normalize_pebble_ui_value(%{type: type, children: children} = value, _eval_context)
       when is_binary(type) and is_list(children) and type not in ["tuple2", "List"] do
    {:ok, normalize_runtime_view_tree_fallback(value)}
  end

  defp normalize_pebble_ui_value(value, eval_context) do
    with {:ok, 1000, windows} <- tagged_constructor_value(value),
         {:ok, windows} <- constructor_list_values(windows),
         {:ok, window_nodes} <-
           normalize_pebble_ui_list(windows, &normalize_pebble_window_node(&1, eval_context)) do
      {:ok, %{"type" => "windowStack", "label" => "", "children" => window_nodes}}
    else
      _ ->
        case normalize_pebble_render_ops_list(value, eval_context) do
          {:ok, node} -> {:ok, node}
          :error -> :error
        end
    end
  end

  @spec normalize_pebble_render_ops_list(EvalTypes.runtime_value(), map()) :: {:ok, map()} | :error
  defp normalize_pebble_render_ops_list(value, eval_context) do
    with {:ok, ops} <- constructor_list_values(value),
         {:ok, op_nodes} <-
           normalize_pebble_ui_list(ops, &normalize_pebble_render_op(&1, eval_context)),
         true <- op_nodes != [] do
      canvas = %{
        "type" => "canvasLayer",
        "label" => "",
        "id" => 1,
        "children" => op_nodes
      }

      window = %{
        "type" => "window",
        "label" => "",
        "id" => 1,
        "children" => [canvas]
      }

      {:ok, %{"type" => "windowStack", "label" => "", "children" => [window]}}
    else
      _ -> :error
    end
  end

  @spec normalize_pebble_window_node(EvalTypes.runtime_value(), map()) :: {:ok, map()} | :error
  defp normalize_pebble_window_node(value, eval_context) do
    with {:ok, 1001, payload} <- tagged_constructor_value(value),
         {:ok, [id, layers]} <- constructor_payload_args(payload, 2),
         {:ok, layers} <- constructor_list_values(layers),
         {:ok, layer_nodes} <-
           normalize_pebble_ui_list(layers, &normalize_pebble_layer_node(&1, eval_context)) do
      {:ok,
       %{
         "type" => "window",
         "label" => "",
         "id" => runtime_expr_scalar(normalize_runtime_view_tree_fallback(id)),
         "children" => layer_nodes
       }}
    else
      _ -> :error
    end
  end

  @spec normalize_pebble_layer_node(EvalTypes.runtime_value(), map()) :: {:ok, map()} | :error
  defp normalize_pebble_layer_node(value, eval_context) do
    with {:ok, 1002, payload} <- tagged_constructor_value(value),
         {:ok, [id, ops]} <- constructor_payload_args(payload, 2),
         {:ok, ops} <- constructor_list_values(ops),
         {:ok, op_nodes} <-
           normalize_pebble_ui_list(ops, &normalize_pebble_render_op(&1, eval_context)) do
      {:ok,
       %{
         "type" => "canvasLayer",
         "label" => "",
         "id" => runtime_expr_scalar(normalize_runtime_view_tree_fallback(id)),
         "children" => op_nodes
       }}
    else
      _ -> :error
    end
  end

  @spec normalize_pebble_render_op(EvalTypes.runtime_value(), map()) :: {:ok, map()} | :error
  defp normalize_pebble_render_op(value, eval_context) do
    case normalize_pebble_context_group(value, eval_context) do
      {:ok, node} ->
        {:ok, node}

      :error ->
        case normalize_pebble_tagged_render_op(value, eval_context) do
          {:ok, node} -> {:ok, node}
          :error -> normalize_pebble_ui_value(value, eval_context)
        end
    end
  end

  @spec normalize_pebble_tagged_render_op(EvalTypes.runtime_value(), map()) :: {:ok, map()} | :error
  defp normalize_pebble_tagged_render_op(value, eval_context) when is_map(eval_context) do
    with {:ok, tag, payload} <- tagged_constructor_value(value),
         type when is_binary(type) <- render_op_type_for_tag(tag),
         {:ok, args} <- render_op_args_for_tag(tag, payload),
         {:ok, fields} <- normalize_render_op_fields(type, args, eval_context) do
      {:ok,
       %{
         "type" => type,
         "label" => "",
         "children" => Enum.map(fields, &normalize_runtime_view_tree_fallback/1)
       }}
    else
      _ -> :error
    end
  end

  defp normalize_pebble_tagged_render_op(_value, _eval_context), do: :error

  @spec render_op_type_for_tag(integer()) :: String.t() | nil
  defp render_op_type_for_tag(1), do: "textInt"
  defp render_op_type_for_tag(2), do: "textLabel"
  defp render_op_type_for_tag(3), do: "text"
  defp render_op_type_for_tag(4), do: "clear"
  defp render_op_type_for_tag(5), do: "pixel"
  defp render_op_type_for_tag(6), do: "line"
  defp render_op_type_for_tag(7), do: "rect"
  defp render_op_type_for_tag(8), do: "fillRect"
  defp render_op_type_for_tag(9), do: "circle"
  defp render_op_type_for_tag(10), do: "fillCircle"
  defp render_op_type_for_tag(12), do: "bitmapInRect"
  defp render_op_type_for_tag(13), do: "rotatedBitmap"
  defp render_op_type_for_tag(14), do: "drawVectorAt"
  defp render_op_type_for_tag(15), do: "vectorSequenceAt"
  defp render_op_type_for_tag(16), do: "pathFilled"
  defp render_op_type_for_tag(17), do: "pathOutline"
  defp render_op_type_for_tag(18), do: "pathOutlineOpen"
  defp render_op_type_for_tag(19), do: "roundRect"
  defp render_op_type_for_tag(20), do: "arc"
  defp render_op_type_for_tag(21), do: "fillRadial"
  defp render_op_type_for_tag(_), do: nil

  @spec render_op_args_for_tag(integer(), EvalTypes.runtime_value()) ::
          {:ok, [EvalTypes.runtime_value()]} | :error
  defp render_op_args_for_tag(tag, payload) do
    case constructor_payload_args(payload, render_op_arg_count(tag)) do
      {:ok, args} -> {:ok, args}
      :error -> :error
    end
  end

  @spec render_op_arg_count(integer()) :: non_neg_integer()
  defp render_op_arg_count(1), do: 3
  defp render_op_arg_count(2), do: 3
  defp render_op_arg_count(3), do: 3
  defp render_op_arg_count(4), do: 1
  defp render_op_arg_count(5), do: 2
  defp render_op_arg_count(6), do: 3
  defp render_op_arg_count(7), do: 2
  defp render_op_arg_count(8), do: 2
  defp render_op_arg_count(9), do: 3
  defp render_op_arg_count(10), do: 3
  defp render_op_arg_count(12), do: 2
  defp render_op_arg_count(13), do: 4
  defp render_op_arg_count(14), do: 2
  defp render_op_arg_count(15), do: 2
  defp render_op_arg_count(16), do: 1
  defp render_op_arg_count(17), do: 1
  defp render_op_arg_count(18), do: 1
  defp render_op_arg_count(19), do: 3
  defp render_op_arg_count(20), do: 6
  defp render_op_arg_count(21), do: 6
  defp render_op_arg_count(_), do: 1

  @spec normalize_render_op_fields(String.t(), [EvalTypes.runtime_value()], map()) ::
          {:ok, [EvalTypes.runtime_value()]} | :error
  defp normalize_render_op_fields("bitmapInRect", [bitmap, bounds | _], eval_context) do
    with {:ok, bitmap_id} <- CoreIREvaluator.bitmap_resource_id_from_value(bitmap, eval_context),
         {:ok, {x, y, w, h}} <- CoreIREvaluator.normalize_runtime_rect(bounds) do
      {:ok, [bitmap_id, x, y, w, h]}
    else
      _ -> :error
    end
  end

  defp normalize_render_op_fields("rotatedBitmap", [bitmap, src_rect, angle, center | _], eval_context) do
    with {:ok, bitmap_id} <- CoreIREvaluator.bitmap_resource_id_from_value(bitmap, eval_context),
         {:ok, {_src_x, _src_y, src_w, src_h}} <- CoreIREvaluator.normalize_runtime_rect(src_rect),
         {:ok, normalized_angle} <- CoreIREvaluator.normalize_runtime_rotation_angle(angle),
         {:ok, {center_x, center_y}} <- CoreIREvaluator.normalize_runtime_point(center) do
      {:ok, [bitmap_id, src_w, src_h, normalized_angle, center_x, center_y]}
    else
      _ -> :error
    end
  end

  defp normalize_render_op_fields("drawVectorAt", [vector, origin | _], eval_context) do
    with vector_id when is_integer(vector_id) <- resolve_render_vector_id(vector, eval_context),
         {:ok, {x, y}} <- CoreIREvaluator.normalize_runtime_point(origin) do
      {:ok, [vector_id, x, y]}
    else
      _ -> :error
    end
  end

  defp normalize_render_op_fields("vectorSequenceAt", [vector, origin | _], eval_context) do
    with vector_id when is_integer(vector_id) <-
           CoreIREvaluator.vector_resource_id_from_value(vector, eval_context),
         {:ok, {x, y}} <- CoreIREvaluator.normalize_runtime_point(origin) do
      {:ok, [vector_id, x, y]}
    else
      _ -> :error
    end
  end

  defp normalize_render_op_fields("fillRect", [bounds, color | _], _eval_context) do
    with {:ok, {x, y, w, h}} <- CoreIREvaluator.normalize_runtime_rect(bounds),
         {:ok, resolved_color} <- CoreIREvaluator.normalize_runtime_color(color) do
      {:ok, [x, y, w, h, resolved_color]}
    else
      _ -> :error
    end
  end

  defp normalize_render_op_fields("clear", [color | _], _eval_context) do
    case CoreIREvaluator.normalize_runtime_color(color) do
      {:ok, resolved_color} -> {:ok, [resolved_color]}
      _ -> :error
    end
  end

  defp normalize_render_op_fields(_type, args, _eval_context) when is_list(args), do: {:ok, args}

  @spec resolve_render_vector_id(EvalTypes.runtime_value(), map()) :: integer() | nil
  defp resolve_render_vector_id(vector, eval_context) when is_map(eval_context) do
    indices = Map.get(eval_context, :vector_resource_indices, %{})
    runtime_model = Map.get(eval_context, :runtime_model, %{})
    from_ctor = vector_ctor_manifest_index(vector, indices)

    from_core =
      case CoreIREvaluator.vector_resource_id_from_value(vector, eval_context) do
        {:ok, id} -> id
        :error -> nil
      end

    from_model = vector_index_from_runtime_model(runtime_model, indices)

    cond do
      is_integer(from_ctor) ->
        from_ctor

      is_integer(from_model) and is_integer(from_core) ->
        min(from_model, from_core)

      is_integer(from_core) ->
        from_core

      is_integer(from_model) ->
        from_model

      true ->
        nil
    end
  end

  defp resolve_render_vector_id(_vector, _eval_context), do: nil

  @spec vector_ctor_manifest_index(EvalTypes.runtime_value(), map()) :: integer() | nil
  defp vector_ctor_manifest_index(%{"ctor" => ctor, "args" => _}, indices) when is_binary(ctor),
    do: vector_index_for_runtime_ctor(ctor, indices)

  defp vector_ctor_manifest_index(%{ctor: ctor, args: _}, indices) when is_binary(ctor),
    do: vector_index_for_runtime_ctor(to_string(ctor), indices)

  defp vector_ctor_manifest_index(_vector, _indices), do: nil

  @spec normalize_pebble_context_group(EvalTypes.runtime_value(), map()) :: {:ok, map()} | :error
  defp normalize_pebble_context_group(value, eval_context) do
    with {:ok, 19, payload} <- tagged_constructor_value(value),
         {:ok, [settings, ops]} <- constructor_payload_args(payload, 2),
         {:ok, settings} <- constructor_list_values(settings),
         {:ok, ops} <- constructor_list_values(ops),
         style <- normalize_pebble_context_style(settings),
         {:ok, op_nodes} <-
           normalize_pebble_ui_list(ops, &normalize_pebble_render_op(&1, eval_context)) do
      {:ok, %{"type" => "group", "label" => "", "style" => style, "children" => op_nodes}}
    else
      _ -> :error
    end
  end

  @spec normalize_pebble_context_style([EvalTypes.runtime_value()]) :: map()
  defp normalize_pebble_context_style(settings) when is_list(settings) do
    Enum.reduce(settings, %{}, fn setting, acc ->
      case normalize_pebble_context_setting(setting) do
        {key, value} -> Map.put(acc, key, value)
        nil -> acc
      end
    end)
  end

  @spec normalize_pebble_context_setting(EvalTypes.runtime_value()) :: {String.t(), EvalTypes.runtime_value()} | nil
  defp normalize_pebble_context_setting(setting) do
    with {:ok, tag, value} <- tagged_constructor_value(setting),
         key when is_binary(key) <- context_setting_key(tag) do
      {key, normalized_context_setting_value(value)}
    else
      _ -> nil
    end
  end

  @spec context_setting_key(EvalTypes.runtime_value()) :: String.t() | nil
  defp context_setting_key(1), do: "stroke_width"
  defp context_setting_key(2), do: "antialiased"
  defp context_setting_key(3), do: "stroke_color"
  defp context_setting_key(4), do: "fill_color"
  defp context_setting_key(5), do: "text_color"
  defp context_setting_key(6), do: "compositing_mode"
  defp context_setting_key(_), do: nil

  @spec normalized_context_setting_value(EvalTypes.runtime_value()) :: EvalTypes.runtime_value()
  defp normalized_context_setting_value(value) when is_integer(value) or is_boolean(value),
    do: value

  defp normalized_context_setting_value(value),
    do: normalized_expr_value(normalize_runtime_view_tree_fallback(value))

  @spec normalize_pebble_ui_list([EvalTypes.runtime_value()], SemTypes.pebble_ui_normalizer()) ::
          {:ok, [map()]} | :error
  defp normalize_pebble_ui_list(values, fun) when is_list(values) and is_function(fun, 1) do
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

  @spec tagged_tuple(EvalTypes.runtime_value()) :: SemTypes.tagged_value()
  defp tagged_tuple({tag, payload}) when is_integer(tag), do: {:ok, tag, payload}
  defp tagged_tuple(_value), do: :error

  @spec tagged_constructor_value(EvalTypes.runtime_value()) :: SemTypes.tagged_value()
  defp tagged_constructor_value(value) do
    case tagged_tuple(value) do
      {:ok, tag, payload} ->
        {:ok, tag, payload}

      :error ->
        normalized_tagged_tuple(value)
    end
  end

  @spec normalized_tagged_tuple(EvalTypes.runtime_value()) :: SemTypes.tagged_value()
  defp normalized_tagged_tuple(%{"type" => "tuple2", "children" => [tag_node, payload]}) do
    case normalized_expr_value(tag_node) do
      tag when is_integer(tag) -> {:ok, tag, payload}
      _ -> :error
    end
  end

  defp normalized_tagged_tuple(%{type: "tuple2", children: [tag_node, payload]}) do
    case normalized_expr_value(tag_node) do
      tag when is_integer(tag) -> {:ok, tag, payload}
      _ -> :error
    end
  end

  defp normalized_tagged_tuple(_value), do: :error

  @spec normalized_expr_value(EvalTypes.runtime_value()) :: EvalTypes.runtime_value()
  defp normalized_expr_value(%{"type" => "expr"} = node), do: Map.get(node, "value")
  defp normalized_expr_value(%{type: "expr"} = node), do: Map.get(node, :value)
  defp normalized_expr_value(_node), do: nil

  @spec constructor_list_values(EvalTypes.runtime_value()) :: SemTypes.tagged_values()
  defp constructor_list_values(values) when is_list(values), do: {:ok, values}

  defp constructor_list_values(%{"type" => "List", "children" => children})
       when is_list(children),
       do: {:ok, children}

  defp constructor_list_values(%{type: "List", children: children}) when is_list(children),
    do: {:ok, children}

  defp constructor_list_values(_values), do: :error

  @spec constructor_payload_args(EvalTypes.runtime_value(), non_neg_integer()) :: SemTypes.tagged_values()
  defp constructor_payload_args(payload, 1), do: {:ok, [payload]}

  defp constructor_payload_args(payload, arity) when is_integer(arity) and arity > 1 do
    case flatten_constructor_payload(payload, arity, []) do
      {:ok, args} -> {:ok, args}
      :error -> :error
    end
  end

  @spec flatten_constructor_payload(EvalTypes.runtime_value(), non_neg_integer(), [EvalTypes.runtime_value()]) ::
          {:ok, [EvalTypes.runtime_value()]} | :error
  defp flatten_constructor_payload(value, 1, acc), do: {:ok, Enum.reverse([value | acc])}

  defp flatten_constructor_payload({left, right}, remaining, acc) when remaining > 1 do
    flatten_constructor_payload(right, remaining - 1, [left | acc])
  end

  defp flatten_constructor_payload(
         %{"type" => "tuple2", "children" => [left, right]},
         remaining,
         acc
       )
       when remaining > 1 do
    flatten_constructor_payload(right, remaining - 1, [left | acc])
  end

  defp flatten_constructor_payload(%{type: "tuple2", children: [left, right]}, remaining, acc)
       when remaining > 1 do
    flatten_constructor_payload(right, remaining - 1, [left | acc])
  end

  defp flatten_constructor_payload(_value, _remaining, _acc), do: :error

  @spec evaluator_context(map(), String.t() | nil) :: SemTypes.eval_context()
  def evaluator_context(core_ir, module_override) do
    module_name =
      case module_override do
        value when is_binary(value) and value != "" -> value
        _ -> CoreIREvaluator.entry_module(core_ir)
      end

    CoreIREvaluator.build_eval_context(core_ir, module_name)
  end

  @spec normalize_runtime_model_by_declared_type(map(), map()) :: map()
  def normalize_runtime_model_by_declared_type(runtime_model, eval_context)
       when is_map(runtime_model) and is_map(eval_context) do
    CoreIREvaluator.normalize_value_by_type(runtime_model, "Model", eval_context)
  end

  def normalize_runtime_model_by_declared_type(runtime_model, _eval_context), do: runtime_model

  @view_runtime_envelope_keys [
    "runtime_model",
    "runtime_view_output",
    "runtime_last_message",
    "runtime_message_source",
    "runtime_message_cursor",
    "runtime_known_messages",
    "runtime_update_branches",
    "runtime_view_tree_sha256",
    "runtime_model_sha256",
    "runtime_model_source",
    "elm_executor_mode",
    "elm_executor",
    "elm_introspect",
    "vector_resource_indices",
    "bitmap_resource_indices",
    "elm_executor_core_ir",
    "elm_executor_core_ir_b64",
    "elm_executor_metadata"
  ]

  @spec enrich_runtime_model_for_view(map(), map()) :: map()
  def enrich_runtime_model_for_view(runtime_model, current_model)
       when is_map(runtime_model) and is_map(current_model) do
    current_model
    |> Map.drop(@view_runtime_envelope_keys)
    |> Map.merge(runtime_model)
  end

  def enrich_runtime_model_for_view(runtime_model, _current_model) when is_map(runtime_model),
    do: runtime_model

  def enrich_runtime_model_for_view(_runtime_model, _current_model), do: %{}

  @spec source_core_ir_fallback(map() | nil, String.t(), String.t() | nil) :: map() | nil
  def source_core_ir_fallback(core_ir, _source, _rel_path) when is_map(core_ir), do: core_ir

  def source_core_ir_fallback(_core_ir, source, rel_path)
       when is_binary(source) and byte_size(source) > 0 do
    path =
      case rel_path do
        value when is_binary(value) and value != "" -> value
        _ -> "Main.elm"
      end

    with {:ok, main_module} <- GeneratedParser.parse_source(path, source),
         extra_modules <- load_resource_modules_for_path(path),
         project <- %Project{
           project_dir: path |> Path.dirname() |> Path.expand(),
           elm_json: %{},
           modules: [main_module | extra_modules],
           diagnostics: []
         },
         {:ok, ir} <- Lowerer.lower_project(project),
         {:ok, core_ir} <- CoreIR.from_ir(ir) do
      core_ir
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  def source_core_ir_fallback(_core_ir, _source, _rel_path), do: nil

  @spec load_resource_modules_for_path(String.t()) :: [map()]
  defp load_resource_modules_for_path(main_path) when is_binary(main_path) do
    resources_path =
      main_path
      |> Path.dirname()
      |> Path.join("Pebble/Ui/Resources.elm")

    case File.read(resources_path) do
      {:ok, source} ->
        case GeneratedParser.parse_source(resources_path, source) do
          {:ok, module} -> [module]
          _ -> []
        end

      _ ->
        []
    end
  end

  @spec vector_resource_indices_context(map(), map()) :: map()
  def vector_resource_indices_context(request, current_model)
       when is_map(request) and is_map(current_model) do
    indices =
      Execution.map_value(request, :vector_resource_indices) ||
        Map.get(current_model, "vector_resource_indices") ||
        Map.get(current_model, :vector_resource_indices)

    case normalize_vector_resource_indices(indices) do
      %{} = normalized when map_size(normalized) > 0 ->
        %{vector_resource_indices: normalized}

      _ ->
        %{}
    end
  end

  def vector_resource_indices_context(_request, _current_model), do: %{}

  @spec bitmap_resource_indices_context(map(), map()) :: map()
  def bitmap_resource_indices_context(request, current_model)
       when is_map(request) and is_map(current_model) do
    indices =
      Execution.map_value(request, :bitmap_resource_indices) ||
        Map.get(current_model, "bitmap_resource_indices") ||
        Map.get(current_model, :bitmap_resource_indices)

    case normalize_bitmap_resource_indices(indices) do
      %{} = normalized when map_size(normalized) > 0 ->
        %{bitmap_resource_indices: normalized}

      _ ->
        %{}
    end
  end

  def bitmap_resource_indices_context(_request, _current_model), do: %{}

  @spec animation_resource_indices_context(map(), map()) :: map()
  def animation_resource_indices_context(request, current_model)
      when is_map(request) and is_map(current_model) do
    indices =
      Execution.map_value(request, :animation_resource_indices) ||
        Map.get(current_model, "animation_resource_indices") ||
        Map.get(current_model, :animation_resource_indices)

    case normalize_animation_resource_indices(indices) do
      %{} = normalized when map_size(normalized) > 0 ->
        %{animation_resource_indices: normalized}

      _ ->
        %{}
    end
  end

  def animation_resource_indices_context(_request, _current_model), do: %{}

  @spec normalize_bitmap_resource_indices(map() | nil) :: map()
  defp normalize_bitmap_resource_indices(indices) when is_map(indices) do
    Enum.reduce(indices, %{}, fn
      {ctor, id}, acc when is_binary(ctor) and is_integer(id) and id >= 1 ->
        Map.put(acc, ctor, id)

      {ctor, id}, acc when is_atom(ctor) and is_integer(id) and id >= 1 ->
        Map.put(acc, Atom.to_string(ctor), id)

      _, acc ->
        acc
    end)
  end

  defp normalize_bitmap_resource_indices(_indices), do: %{}

  @spec normalize_animation_resource_indices(map() | nil) :: map()
  defp normalize_animation_resource_indices(indices) when is_map(indices) do
    Enum.reduce(indices, %{}, fn
      {ctor, id}, acc when is_binary(ctor) and is_integer(id) and id >= 1 ->
        Map.put(acc, ctor, id)

      {ctor, id}, acc when is_atom(ctor) and is_integer(id) and id >= 1 ->
        Map.put(acc, Atom.to_string(ctor), id)

      _, acc ->
        acc
    end)
  end

  defp normalize_animation_resource_indices(_indices), do: %{}

  @spec normalize_vector_resource_indices(map() | nil) :: map()
  defp normalize_vector_resource_indices(indices) when is_map(indices) do
    Enum.reduce(indices, %{}, fn
      {ctor, id}, acc when is_binary(ctor) and is_integer(id) and id >= 1 ->
        Map.put(acc, ctor, id)

      {ctor, id}, acc when is_atom(ctor) and is_integer(id) and id >= 1 ->
        Map.put(acc, Atom.to_string(ctor), id)

      _, acc ->
        acc
    end)
  end

  defp normalize_vector_resource_indices(_indices), do: %{}

  @spec normalize_launch_context(SemTypes.launch_context()) :: SemTypes.launch_context()
  def normalize_launch_context(context) when is_map(context) do
    reason =
      case Execution.map_value(context, :reason) do
        %{"ctor" => _} = value -> value
        %{ctor: _} = value -> value
        value when is_binary(value) -> %{"ctor" => value, "args" => []}
        _ -> launch_reason_value(Execution.map_value(context, :launch_reason))
      end

    screen =
      case Execution.map_value(context, :screen) do
        value when is_map(value) ->
          launch_context_screen(value, context)

        _ ->
          launch_context_screen(%{}, context)
      end

    context
    |> Map.put("reason", reason)
    |> Map.put(
      "watchModel",
      Execution.map_value(context, :watch_model) || Execution.map_value(context, :watchModel) || "Basalt"
    )
    |> Map.put(
      "watchProfileId",
      Execution.map_value(context, :watch_profile_id) || Execution.map_value(context, :watchProfileId) || "basalt"
    )
    |> Map.put("screen", screen)
    |> Map.put(
      "hasMicrophone",
      Execution.map_value(context, :has_microphone) || Execution.map_value(context, :hasMicrophone) || false
    )
    |> Map.put(
      "hasCompass",
      Execution.map_value(context, :has_compass) || Execution.map_value(context, :hasCompass) || false
    )
    |> Map.put(
      "supportsHealth",
      Execution.map_value(context, :supports_health) || Execution.map_value(context, :supportsHealth) || false
    )
  end

  def normalize_launch_context(_context) do
    normalize_launch_context(%{})
  end

  @spec launch_context_from_model(map()) :: map()
  def launch_context_from_model(model) when is_map(model) do
    Map.get(model, "launch_context") || Map.get(model, :launch_context) || %{}
  end

  def launch_context_from_model(_model), do: %{}

  @spec launch_context_screen(map(), map()) :: map()
  defp launch_context_screen(screen, context) when is_map(screen) and is_map(context) do
    shape_name = launch_context_display_shape(screen, context)
    color_name = launch_context_color_mode_value(screen, context)

    %{
      "width" => Execution.map_value(screen, :width) || Execution.map_value(context, :screenW) || 144,
      "height" => Execution.map_value(screen, :height) || Execution.map_value(context, :screenH) || 168,
      "shape" => launch_context_display_shape_ctor(shape_name),
      "color_mode" => color_name,
      "colorMode" => launch_context_color_mode_ctor(color_name)
    }
  end

  @spec launch_context_display_shape_ctor(String.t()) :: map()
  defp launch_context_display_shape_ctor("Round"), do: %{"ctor" => "Round", "args" => []}
  defp launch_context_display_shape_ctor(_), do: %{"ctor" => "Rectangular", "args" => []}

  @spec launch_context_color_mode_ctor(String.t()) :: map()
  defp launch_context_color_mode_ctor("BlackWhite"), do: %{"ctor" => "BlackWhite", "args" => []}
  defp launch_context_color_mode_ctor("Color"), do: %{"ctor" => "Color", "args" => []}
  defp launch_context_color_mode_ctor(_), do: %{"ctor" => "Color", "args" => []}

  @spec launch_context_display_shape(map(), map()) :: String.t()
  defp launch_context_display_shape(screen, context) when is_map(screen) and is_map(context) do
    cond do
      Execution.map_value(screen, :shape) in ["Round", "Rectangular"] ->
        Execution.map_value(screen, :shape)

      Execution.map_value(screen, :shape) == "round" ->
        "Round"

      Execution.map_value(screen, :shape) == "rect" ->
        "Rectangular"

      Execution.map_value(screen, :is_round) == true or Execution.map_value(screen, :isRound) == true ->
        "Round"

      Execution.map_value(screen, :is_round) == false or Execution.map_value(screen, :isRound) == false ->
        "Rectangular"

      Execution.map_value(context, :shape) == "round" ->
        "Round"

      Execution.map_value(context, :shape) == "rect" ->
        "Rectangular"

      true ->
        "Rectangular"
    end
  end

  @spec launch_context_color_mode_value(map(), map()) :: String.t()
  defp launch_context_color_mode_value(screen, context) when is_map(screen) and is_map(context) do
    cond do
      Execution.map_value(screen, :color_mode) in ["Color", "BlackWhite"] ->
        Execution.map_value(screen, :color_mode)

      Execution.map_value(screen, :colorMode) in ["Color", "BlackWhite"] ->
        Execution.map_value(screen, :colorMode)

      Execution.map_value(screen, :is_color) == true or Execution.map_value(screen, :isColor) == true ->
        "Color"

      Execution.map_value(screen, :is_color) == false or Execution.map_value(screen, :isColor) == false ->
        "BlackWhite"

      Execution.map_value(context, :is_color) == true ->
        "Color"

      Execution.map_value(context, :is_color) == false ->
        "BlackWhite"

      true ->
        "Color"
    end
  end

  @spec launch_reason_value(String.t()) :: map()
  defp launch_reason_value(value) when is_binary(value) and value != "",
    do: %{"ctor" => value, "args" => []}

  defp launch_reason_value(_value), do: %{"ctor" => "LaunchUser", "args" => []}

  @spec derive_view_output(map(), map(), map()) :: SemTypes.view_output()
  def derive_view_output(view_tree, runtime_model, eval_context)
       when is_map(view_tree) and is_map(runtime_model) and is_map(eval_context) do
    view_output_from_tree(view_tree, runtime_model, eval_context)
  end

  def derive_view_output(_view_tree, _runtime_model, _eval_context), do: []

  @spec view_output_from_tree(map(), map(), map()) :: SemTypes.view_output()
  defp view_output_from_tree(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    type =
      node
      |> Map.get("type", Map.get(node, :type, ""))
      |> to_string()

    children =
      case Map.get(node, "children") || Map.get(node, :children) do
        list when is_list(list) -> list
        _ -> []
      end

    case type do
      "group" ->
        style_rows = view_output_style_rows(node)

        child_rows =
          Enum.flat_map(children, &view_output_from_tree(&1, runtime_model, eval_context))

        if style_rows == [] do
          child_rows
        else
          [%{"kind" => "push_context"}] ++
            style_rows ++ child_rows ++ [%{"kind" => "pop_context"}]
        end

      "if" ->
        case ViewTreeEval.selected_if_branch(children, runtime_model, eval_context) do
          %{} = branch -> view_output_from_tree(branch, runtime_model, eval_context)
          _ -> []
        end

      "let" ->
        case ViewTreeEval.apply_let_view_binding(node, runtime_model, eval_context) do
          {%{} = inner, ctx} -> view_output_from_tree(inner, runtime_model, ctx)
          _ -> []
        end

      type
      when type in [
             "root",
             "windowStack",
             "window",
             "canvasLayer",
             "List",
             "append",
             "__append__",
             "toUiNode",
             "call",
             "expr",
             "tuple2",
             "CanvasLayer",
             "case"
           ] ->
        Enum.flat_map(children, &view_output_from_tree(&1, runtime_model, eval_context))

      _ ->
        view_output_from_node(node, runtime_model, eval_context)
    end
  end

  defp view_output_from_tree(_node, _runtime_model, _eval_context), do: []

  @spec view_output_style_rows(map()) :: [SemTypes.view_output_row()]
  defp view_output_style_rows(node) when is_map(node) do
    style = Map.get(node, "style") || Map.get(node, :style) || %{}

    if is_map(style) do
      [
        style_row(style, "stroke_width", "stroke_width", "value"),
        style_row(style, "antialiased", "antialiased", "value"),
        style_row(style, "stroke_color", "stroke_color", "color"),
        style_row(style, "fill_color", "fill_color", "color"),
        style_row(style, "text_color", "text_color", "color"),
        style_row(style, "compositing_mode", "compositing_mode", "value")
      ]
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  defp view_output_style_rows(_node), do: []

  @spec style_row(map(), String.t(), String.t(), String.t()) :: map() | nil
  defp style_row(style, source_key, kind, value_key)
       when is_map(style) and is_binary(source_key) and is_binary(kind) and is_binary(value_key) do
    case style_value(style, source_key) do
      nil -> nil
      value -> %{"kind" => kind, value_key => value}
    end
  end

  @spec style_value(map(), String.t()) :: EvalTypes.runtime_value() | nil
  defp style_value(style, key) when is_map(style) and is_binary(key) do
    case Map.fetch(style, key) do
      {:ok, value} ->
        value

      :error ->
        Enum.find_value(style, fn
          {atom_key, value} when is_atom(atom_key) ->
            if Atom.to_string(atom_key) == key, do: value, else: nil

          _ ->
            nil
        end)
    end
  end

  @spec view_output_from_node(map(), map(), map()) :: SemTypes.view_output()
  defp view_output_from_node(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    type =
      node
      |> Map.get("type", Map.get(node, :type, ""))
      |> to_string()

    ints = node_int_args(node, runtime_model, eval_context)

    rows =
      case type do
        "clear" ->
          case clear_args_from_node(node, ints, runtime_model, eval_context) do
            {:ok, [color]} ->
              [%{"kind" => "clear", "color" => color}]

            :error ->
              [unresolved_view_output_row(node, type, ints, 1)]
          end

        "roundRect" ->
          case round_rect_args_from_node(node, ints, runtime_model, eval_context) do
            {:ok, [x, y, w, h, radius, fill]} ->
              [
                %{
                  "kind" => "round_rect",
                  "x" => x,
                  "y" => y,
                  "w" => w,
                  "h" => h,
                  "radius" => radius,
                  "fill" => fill
                }
              ]

            :error ->
              [unresolved_view_output_row(node, type, ints, 6)]
          end

        "rect" ->
          case rect_color_args_from_node(node, ints, runtime_model, eval_context) do
            {:ok, [x, y, w, h, fill]} ->
              [%{"kind" => "rect", "x" => x, "y" => y, "w" => w, "h" => h, "fill" => fill}]

            :error ->
              [unresolved_view_output_row(node, type, ints, 5)]
          end

        "fillRect" ->
          case rect_color_args_from_node(node, ints, runtime_model, eval_context) do
            {:ok, [x, y, w, h, fill]} ->
              [%{"kind" => "fill_rect", "x" => x, "y" => y, "w" => w, "h" => h, "fill" => fill}]

            :error ->
              [unresolved_view_output_row(node, type, ints, 5)]
          end

        "line" ->
          case line_args_from_node(node, ints, runtime_model, eval_context) do
            {:ok, [x1, y1, x2, y2, color]} ->
              [
                %{
                  "kind" => "line",
                  "x1" => x1,
                  "y1" => y1,
                  "x2" => x2,
                  "y2" => y2,
                  "color" => color
                }
              ]

            _ ->
              [unresolved_view_output_row(node, type, ints, 5)]
          end

        "arc" ->
          case rect_angle_args_from_node(node, ints, runtime_model, eval_context) do
            {:ok, [x, y, w, h, start_angle, end_angle]} ->
              [
                %{
                  "kind" => "arc",
                  "x" => x,
                  "y" => y,
                  "w" => w,
                  "h" => h,
                  "start_angle" => start_angle,
                  "end_angle" => end_angle
                }
              ]

            :error ->
              [unresolved_view_output_row(node, type, ints, 6)]
          end

        "fillRadial" ->
          case rect_angle_args_from_node(node, ints, runtime_model, eval_context) do
            {:ok, [x, y, w, h, start_angle, end_angle]} ->
              [
                %{
                  "kind" => "fill_radial",
                  "x" => x,
                  "y" => y,
                  "w" => w,
                  "h" => h,
                  "start_angle" => start_angle,
                  "end_angle" => end_angle
                }
              ]

            :error ->
              [unresolved_view_output_row(node, type, ints, 6)]
          end

        "pathFilled" ->
          case path_args_from_node(node, runtime_model, eval_context) do
            {:ok, %{points: points, offset_x: offset_x, offset_y: offset_y, rotation: rotation}} ->
              [
                %{
                  "kind" => "path_filled",
                  "points" => points,
                  "offset_x" => offset_x,
                  "offset_y" => offset_y,
                  "rotation" => rotation
                }
              ]

            :error ->
              [unresolved_view_output_row(node, type, ints, 4)]
          end

        "pathOutline" ->
          case path_args_from_node(node, runtime_model, eval_context) do
            {:ok, %{points: points, offset_x: offset_x, offset_y: offset_y, rotation: rotation}} ->
              [
                %{
                  "kind" => "path_outline",
                  "points" => points,
                  "offset_x" => offset_x,
                  "offset_y" => offset_y,
                  "rotation" => rotation
                }
              ]

            :error ->
              [unresolved_view_output_row(node, type, ints, 4)]
          end

        "pathOutlineOpen" ->
          case path_args_from_node(node, runtime_model, eval_context) do
            {:ok, %{points: points, offset_x: offset_x, offset_y: offset_y, rotation: rotation}} ->
              [
                %{
                  "kind" => "path_outline_open",
                  "points" => points,
                  "offset_x" => offset_x,
                  "offset_y" => offset_y,
                  "rotation" => rotation
                }
              ]

            :error ->
              [unresolved_view_output_row(node, type, ints, 4)]
          end

        "circle" ->
          case circle_args_from_node(node, ints, runtime_model, eval_context) do
            {:ok, [cx, cy, r, color]} ->
              [%{"kind" => "circle", "cx" => cx, "cy" => cy, "r" => r, "color" => color}]

            _ ->
              [unresolved_view_output_row(node, type, ints, 4)]
          end

        "fillCircle" ->
          case circle_args_from_node(node, ints, runtime_model, eval_context) do
            {:ok, [cx, cy, r, color]} ->
              [%{"kind" => "fill_circle", "cx" => cx, "cy" => cy, "r" => r, "color" => color}]

            _ ->
              [unresolved_view_output_row(node, type, ints, 4)]
          end

        "bitmapInRect" ->
          case require_ints(ints, 5) do
            {:ok, [bitmap_id, x, y, w, h]} ->
              [
                %{
                  "kind" => "bitmap_in_rect",
                  "bitmap_id" => bitmap_id,
                  "x" => x,
                  "y" => y,
                  "w" => w,
                  "h" => h
                }
              ]

            :error ->
              [unresolved_view_output_row(node, type, ints, 5)]
          end

        "rotatedBitmap" ->
          case require_ints(ints, 6) do
            {:ok, [bitmap_id, src_w, src_h, angle, center_x, center_y]} ->
              [
                %{
                  "kind" => "rotated_bitmap",
                  "bitmap_id" => bitmap_id,
                  "src_w" => src_w,
                  "src_h" => src_h,
                  "angle" => angle,
                  "center_x" => center_x,
                  "center_y" => center_y
                }
              ]

            :error ->
              [unresolved_view_output_row(node, type, ints, 6)]
          end

        type when type in ["drawVectorAt", "vectorAt"] ->
          case vector_at_args_from_node(node, ints, runtime_model, eval_context) do
            {:ok, [vector_id, x, y]} ->
              [%{"kind" => "vector_at", "vector_id" => vector_id, "x" => x, "y" => y}]

            :error ->
              [unresolved_view_output_row(node, type, ints, 3)]
          end

        type when type in ["drawVectorSequenceAt", "vectorSequenceAt"] ->
          case vector_at_args_from_node(node, ints, runtime_model, eval_context) do
            {:ok, [vector_id, x, y]} ->
              [
                %{"kind" => "vector_sequence_at", "vector_id" => vector_id, "x" => x, "y" => y}
              ]

            :error ->
              [unresolved_view_output_row(node, type, ints, 3)]
          end

        type when type in ["drawBitmapSequenceAt", "bitmapSequenceAt"] ->
          case animation_at_args_from_node(node, ints, runtime_model, eval_context) do
            {:ok, [animation_id, x, y]} ->
              [
                %{"kind" => "bitmap_sequence_at", "animation_id" => animation_id, "x" => x, "y" => y}
              ]

            :error ->
              [unresolved_view_output_row(node, type, ints, 3)]
          end

        "pixel" ->
          case require_ints(ints, 3) do
            {:ok, [x, y, color]} ->
              [%{"kind" => "pixel", "x" => x, "y" => y, "color" => color}]

            :error ->
              [unresolved_view_output_row(node, type, ints, 3)]
          end

        "textInt" ->
          case text_int_args_from_node(node, ints, runtime_model, eval_context) do
            {:ok, [font_id, x, y, value]} when is_integer(font_id) and is_integer(value) ->
              [
                %{
                  "kind" => "text_int",
                  "x" => x,
                  "y" => y,
                  "text" => Integer.to_string(value),
                  "font_id" => font_id
                }
              ]

            _ ->
              [unresolved_view_output_row(node, type, ints, 4)]
          end

        "textLabel" ->
          case text_label_args_from_node(node, ints, runtime_model, eval_context) do
            {:ok, [font_id, x, y]} when is_integer(font_id) ->
              [
                %{
                  "kind" => "text_label",
                  "x" => x,
                  "y" => y,
                  "text" => text_label_from_node(node, runtime_model, eval_context),
                  "font_id" => font_id
                }
              ]

            _ ->
              [unresolved_view_output_row(node, type, ints, 3)]
          end

        "text" ->
          case text_args_from_node(node, ints, runtime_model, eval_context) do
            {:ok, [font_id, x, y, w, h, alignment, overflow, text]}
            when is_integer(font_id) and is_integer(x) and is_integer(y) and is_integer(w) and
                   is_integer(h) and is_binary(text) ->
              [
                %{
                  "kind" => "text",
                  "x" => x,
                  "y" => y,
                  "w" => w,
                  "h" => h,
                  "text" => text,
                  "font_id" => font_id,
                  "text_align" => text_alignment_name(alignment),
                  "text_overflow" => text_overflow_name(overflow)
                }
              ]

            _ ->
              [unresolved_view_output_row(node, type, ints, 6)]
          end

        _ ->
          view_output_from_introspect_helper(node, runtime_model, eval_context)
      end

    Enum.map(rows, &put_view_output_source(&1, node))
  end

  defp view_output_from_node(_node, _runtime_model, _eval_context), do: []

  @spec view_output_from_introspect_helper(map(), map(), map()) :: SemTypes.view_output()
  defp view_output_from_introspect_helper(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    case helper_return_kind(node, eval_context) do
      :list_render_op -> view_output_from_list_render_op_helper(node, runtime_model, eval_context)
      :render_op -> view_output_from_render_op_helper(node, runtime_model, eval_context)
      _ -> []
    end
  end

  defp view_output_from_introspect_helper(_node, _runtime_model, _eval_context), do: []

  @spec view_output_from_list_render_op_helper(map(), map(), map()) :: SemTypes.view_output()
  defp view_output_from_list_render_op_helper(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    call_site_rows =
      node
      |> ViewTreeEval.node_children()
      |> Enum.flat_map(&collect_subtree_view_output(&1, runtime_model, eval_context))

    if call_site_rows != [] do
      call_site_rows
    else
      view_output_from_helper_function_body(node, runtime_model, eval_context)
    end
  end

  defp view_output_from_list_render_op_helper(_node, _runtime_model, _eval_context), do: []

  @spec view_output_from_helper_function_body(map(), map(), map()) :: SemTypes.view_output()
  defp view_output_from_helper_function_body(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    with %{} = ei <- Map.get(eval_context, :elm_introspect),
         target when is_binary(target) <- view_tree_helper_target(node),
         {module_name, function_name} <- resolve_helper_function(ei, target),
         arity <- helper_call_arity(node),
         key <- "#{module_name}|#{function_name}|#{arity}",
         %{} = body_tree <-
           get_in(ei, ["function_view_trees", key]) ||
             get_in(ei, [:function_view_trees, key]) do
      eval_context =
        eval_context
        |> Map.put(:view_param_bindings, helper_param_bindings(node, runtime_model, eval_context, key, ei))

      collect_subtree_view_output(body_tree, runtime_model, eval_context)
    else
      _ -> []
    end
  end

  defp view_output_from_helper_function_body(_node, _runtime_model, _eval_context), do: []

  @spec helper_param_bindings(map(), map(), map(), String.t(), map()) :: map()
  defp helper_param_bindings(call_node, runtime_model, eval_context, function_key, ei)
       when is_map(call_node) and is_map(runtime_model) and is_map(eval_context) and is_binary(function_key) and
              is_map(ei) do
    arg_names = Map.get(call_node, "arg_names") || []
    param_types = helper_param_types(ei, function_key, length(arg_names))

    call_node
    |> ViewTreeEval.node_children()
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {child, index}, acc ->
      name = Enum.at(arg_names, index)
      type = Enum.at(param_types, index)

      if is_binary(name) and name != "" do
        value =
          case ViewTreeEval.evaluate_view_tree_value(child, runtime_model, eval_context) do
            nil -> fallback_helper_param_value(type, runtime_model)
            bound -> bound
          end

        if is_nil(value), do: acc, else: Map.put(acc, name, value)
      else
        acc
      end
    end)
  end

  defp helper_param_bindings(_call_node, _runtime_model, _eval_context, _function_key, _ei), do: %{}

  @spec helper_param_types(map(), String.t(), non_neg_integer()) :: [String.t()]
  defp helper_param_types(ei, function_key, arity) when is_map(ei) and is_binary(function_key) do
    case Map.get(Map.get(ei, "function_types") || %{}, function_key) do
      signature when is_binary(signature) ->
        signature
        |> String.split("->")
        |> Enum.map(&String.trim/1)
        |> Enum.take(arity)

      _ ->
        []
    end
  end

  @spec fallback_helper_param_value(String.t() | nil, map()) :: EvalTypes.runtime_value()
  defp fallback_helper_param_value(type, runtime_model) when is_map(runtime_model) do
    normalized = if is_binary(type), do: String.downcase(type), else: ""

    cond do
      String.contains?(normalized, "point") ->
        case {model_screen_dimension(runtime_model, "screenW"), model_screen_dimension(runtime_model, "screenH")} do
          {w, h} when is_integer(w) and is_integer(h) ->
            %{"ctor" => "Point", "args" => [div(w, 2), div(h, 2)]}

          _ ->
            nil
        end

      true ->
        nil
    end
  end

  defp fallback_helper_param_value(_type, _runtime_model), do: nil

  @spec view_output_from_render_op_helper(map(), map(), map()) :: SemTypes.view_output()
  defp view_output_from_render_op_helper(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    children = ViewTreeEval.node_children(node)

    with [_model_node, _color_node, y_node, height_node, text_node | _] <- children,
         y when is_integer(y) <- ViewTreeEval.eval_view_int(y_node, runtime_model, eval_context),
         height when is_integer(height) <- ViewTreeEval.eval_view_int(height_node, runtime_model, eval_context),
         w when is_integer(w) <- model_screen_dimension(runtime_model, "screenW"),
         text when is_binary(text) <- helper_string_value(text_node, runtime_model, eval_context) do
      [%{
        "kind" => "text",
        "x" => 0,
        "y" => y,
        "w" => w,
        "h" => height,
        "text" => text,
        "font_id" => 0,
        "text_align" => "center",
        "text_overflow" => "fill"
      }]
    else
      _ ->
        Enum.flat_map(children, &view_output_from_tree(&1, runtime_model, eval_context))
    end
  end

  defp view_output_from_render_op_helper(_node, _runtime_model, _eval_context), do: []

  @spec helper_string_value(map(), map(), map()) :: String.t() | nil
  defp helper_string_value(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    ViewTreeEval.eval_view_text(node, runtime_model, eval_context)
  end

  defp helper_string_value(_node, _runtime_model, _eval_context), do: nil

  @subtree_container_types ~w(
    root windowStack window canvasLayer List append __append__ toUiNode call expr tuple2
    CanvasLayer case if Then Else In record field var qualified_call constructor_call
  )

  @spec collect_subtree_view_output(map(), map(), map()) :: SemTypes.view_output()
  defp collect_subtree_view_output(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    type = view_tree_node_type(node)

    node_rows =
      if type in @subtree_container_types do
        []
      else
        view_output_from_node(node, runtime_model, eval_context)
      end

    child_rows =
      node
      |> ViewTreeEval.node_children()
      |> Enum.flat_map(&collect_subtree_view_output(&1, runtime_model, eval_context))

    node_rows ++ child_rows
  end

  defp collect_subtree_view_output(_node, _runtime_model, _eval_context), do: []

  @spec view_tree_node_type(map()) :: String.t()
  defp view_tree_node_type(node) when is_map(node) do
    node
    |> Map.get("type", Map.get(node, :type, ""))
    |> to_string()
  end

  defp view_tree_node_type(_node), do: ""

  @spec model_screen_dimension(map(), String.t()) :: integer() | nil
  defp model_screen_dimension(runtime_model, key) when is_map(runtime_model) and is_binary(key) do
    aliases =
      case key do
        "screenW" -> ["screenW", "screen_width", "screenWidth"]
        "screenH" -> ["screenH", "screen_height", "screenHeight"]
        _ -> [key]
      end

    Enum.find_value(aliases, fn alias_key ->
      case ViewTreeEval.model_value_by_key(runtime_model, alias_key) do
        value when is_integer(value) -> value
        _ -> nil
      end
    end)
  end

  defp model_screen_dimension(_runtime_model, _key), do: nil

  @spec helper_return_kind(map(), map()) :: :list_render_op | :render_op | :string | :unknown
  defp helper_return_kind(node, eval_context) when is_map(node) and is_map(eval_context) do
    with %{} = ei <- Map.get(eval_context, :elm_introspect),
         target when is_binary(target) <- view_tree_helper_target(node),
         {module_name, function_name} <- resolve_helper_function(ei, target),
         arity <- helper_call_arity(node),
         key <- "#{module_name}|#{function_name}|#{arity}",
         signature when is_binary(signature) <-
           Map.get(Map.get(ei, "function_types") || %{}, key) do
      normalized =
        signature
        |> String.replace(~r/\s+/, "")
        |> String.downcase()

      cond do
        String.match?(normalized, ~r/list.*renderop/) -> :list_render_op
        String.match?(normalized, ~r/->renderop$/) -> :render_op
        String.match?(normalized, ~r/->.*string$/) -> :string
        true -> :unknown
      end
    else
      _ -> :unknown
    end
  end

  defp helper_return_kind(_node, _eval_context), do: :unknown

  @spec view_tree_helper_target(map()) :: String.t() | nil
  defp view_tree_helper_target(node) when is_map(node) do
    Map.get(node, "qualified_target") ||
      case {Map.get(node, "label"), Map.get(node, "type")} do
        {name, name} when is_binary(name) -> name
        {label, _} when is_binary(label) -> label
        {_, type} when is_binary(type) -> type
        _ -> nil
      end
  end

  defp view_tree_helper_target(_node), do: nil

  @spec resolve_helper_function(map(), String.t()) :: {String.t(), String.t()} | nil
  defp resolve_helper_function(ei, target) when is_map(ei) and is_binary(target) do
    module_name = Map.get(ei, "module")

    cond do
      is_binary(module_name) and not String.contains?(target, ".") ->
        {module_name, target}

      String.contains?(target, ".") ->
        case String.split(target, ".") do
          [mod, fun] -> {mod, fun}
          _ -> nil
        end

      true ->
        nil
    end
  end

  defp resolve_helper_function(_ei, _target), do: nil

  @spec helper_call_arity(map()) :: non_neg_integer()
  defp helper_call_arity(node) when is_map(node) do
    node
    |> ViewTreeEval.node_children()
    |> length()
  end

  defp helper_call_arity(_node), do: 0

  @spec put_view_output_source(SemTypes.view_output_row(), map()) :: SemTypes.view_output_row()
  defp put_view_output_source(row, node) when is_map(row) and is_map(node) do
    case Map.get(node, "source") || Map.get(node, :source) do
      %{} = source -> Map.put(row, "source", source)
      _ -> row
    end
  end

  defp put_view_output_source(row, _node), do: row

  @spec annotate_view_output_sources(SemTypes.view_output(), map()) :: SemTypes.view_output()
  def annotate_view_output_sources(rows, introspect) when is_list(rows) and is_map(introspect) do
    source_locations =
      Execution.map_value(introspect, :view_source_locations)
      |> case do
        %{} = value -> value
        _ -> %{}
      end

    {annotated, _counters} =
      Enum.map_reduce(rows, %{}, fn row, counters ->
        kind = if is_map(row), do: to_string(Execution.map_value(row, :kind) || "")

        cond do
          not is_map(row) ->
            {row, counters}

          Execution.map_value(row, :source) != nil ->
            {row, increment_view_output_counter(counters, kind)}

          kind == "" ->
            {row, counters}

          true ->
            index = Map.get(counters, kind, 0)

            source =
              source_locations
              |> Map.get(kind)
              |> source_location_at(index)

            row =
              case source do
                %{} = source -> Map.put(row, "source", source)
                _ -> row
              end

            {row, increment_view_output_counter(counters, kind)}
        end
      end)

    annotated
  end

  def annotate_view_output_sources(rows, _introspect) when is_list(rows), do: rows

  @spec increment_view_output_counter(map(), String.t() | nil) :: map()
  defp increment_view_output_counter(counters, kind)
       when is_map(counters) and is_binary(kind) and kind != "" do
    Map.update(counters, kind, 1, &(&1 + 1))
  end

  defp increment_view_output_counter(counters, _kind), do: counters

  @spec source_location_at([map()], non_neg_integer()) :: map() | nil
  defp source_location_at(locations, index) when is_list(locations) and locations != [] do
    Enum.at(locations, index) || List.last(locations)
  end

  defp source_location_at(_locations, _index), do: nil

  @spec node_int_args(map(), map(), map()) :: [integer()]
  defp node_int_args(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    label = (node["label"] || node[:label] || "") |> to_string()
    from_label = ViewTreeEval.extract_ints(label)
    from_fields = node_int_args_from_fields(node)
    min_arity = min_int_arity_for_node(node)

    cond do
      from_fields != [] and length(from_fields) >= min_arity ->
        from_fields

      from_label != [] and length(from_label) >= min_arity ->
        from_label

      true ->
        children =
          case node["children"] || node[:children] do
            list when is_list(list) -> list
            _ -> []
          end

        children
        |> Enum.filter(&is_map/1)
        |> Enum.map(&ViewTreeEval.eval_view_int(&1, runtime_model, eval_context))
        |> Enum.reject(&is_nil/1)
    end
  end

  defp node_int_args(_node, _runtime_model, _eval_context), do: []

  @spec node_int_args_from_fields(map()) :: [integer()]
  defp node_int_args_from_fields(node) when is_map(node) do
    node
    |> Map.get("type", Map.get(node, :type))
    |> runtime_node_arg_fields()
    |> Enum.map(fn field -> Map.get(node, field) || Map.get(node, String.to_atom(field)) end)
    |> Enum.filter(&is_integer/1)
  end

  @spec min_int_arity_for_node(map()) :: non_neg_integer()
  defp min_int_arity_for_node(node) when is_map(node) do
    type = to_string(node["type"] || node[:type] || "")

    case type do
      "clear" -> 1
      "roundRect" -> 6
      "rect" -> 5
      "fillRect" -> 5
      "line" -> 5
      "arc" -> 6
      "fillRadial" -> 6
      "pathFilled" -> 4
      "pathOutline" -> 4
      "pathOutlineOpen" -> 4
      "circle" -> 4
      "fillCircle" -> 4
      "bitmapInRect" -> 5
      "rotatedBitmap" -> 6
      "drawVectorAt" -> 3
      "vectorAt" -> 3
      "drawVectorSequenceAt" -> 3
      "vectorSequenceAt" -> 3
      "drawBitmapSequenceAt" -> 3
      "bitmapSequenceAt" -> 3
      "pixel" -> 3
      "textInt" -> 4
      "textLabel" -> 3
      _ -> 1
    end
  end

  @spec require_ints([integer()], non_neg_integer()) :: {:ok, [integer()]} | :error
  defp require_ints(values, required)
       when is_list(values) and is_integer(required) and required > 0 do
    if length(values) >= required do
      head = Enum.take(values, required)
      if Enum.all?(head, &is_integer/1), do: {:ok, head}, else: :error
    else
      :error
    end
  end

  defp require_ints(_values, _required), do: :error

  @spec unresolved_view_output_row(map(), String.t(), [integer()], non_neg_integer()) :: SemTypes.view_output_row()
  defp unresolved_view_output_row(node, node_type, ints, required_arity)
       when is_map(node) and is_binary(node_type) and is_list(ints) and is_integer(required_arity) do
    %{
      "kind" => "unresolved",
      "node_type" => node_type,
      "label" => to_string(node["label"] || node[:label] || ""),
      "provided_int_count" => length(ints),
      "required_int_count" => required_arity
    }
  end

  @spec vector_at_args_from_node(map(), [integer()], map(), map()) :: SemTypes.draw_args()
  defp vector_at_args_from_node(node, ints, runtime_model, eval_context)
       when is_map(node) and is_list(ints) and is_map(runtime_model) and is_map(eval_context) do
    case require_ints(ints, 3) do
      {:ok, [vector_id, x, y]} ->
        {:ok, [vector_id, x, y]}

      :error ->
        case ViewTreeEval.node_children(node) do
          [vector_node, x_node, y_node | _] ->
            with vector_id when is_integer(vector_id) <-
                   preview_vector_id(vector_node, runtime_model, eval_context),
                 x when is_integer(x) <- ViewTreeEval.eval_view_int(x_node, runtime_model, eval_context),
                 y when is_integer(y) <- ViewTreeEval.eval_view_int(y_node, runtime_model, eval_context) do
              {:ok, [vector_id, x, y]}
            else
              _ -> :error
            end

          [vector_node, point_node | _] ->
            with vector_id when is_integer(vector_id) <-
                   preview_vector_id(vector_node, runtime_model, eval_context),
                 {:ok, [x, y]} <- point_pair_from_node(point_node, runtime_model, eval_context) do
              {:ok, [vector_id, x, y]}
            else
              _ -> :error
            end

          _ ->
            :error
        end
    end
  end

  defp vector_at_args_from_node(_node, _ints, _runtime_model, _eval_context), do: :error

  @spec animation_at_args_from_node(map(), [integer()], map(), map()) :: SemTypes.draw_args()
  defp animation_at_args_from_node(node, ints, runtime_model, eval_context)
       when is_map(node) and is_list(ints) and is_map(runtime_model) and is_map(eval_context) do
    case require_ints(ints, 3) do
      {:ok, [animation_id, x, y]} ->
        {:ok, [animation_id, x, y]}

      :error ->
        case ViewTreeEval.node_children(node) do
          [animation_node, x_node, y_node | _] ->
            with animation_id when is_integer(animation_id) <-
                   preview_animation_id(animation_node, runtime_model, eval_context),
                 x when is_integer(x) <- ViewTreeEval.eval_view_int(x_node, runtime_model, eval_context),
                 y when is_integer(y) <- ViewTreeEval.eval_view_int(y_node, runtime_model, eval_context) do
              {:ok, [animation_id, x, y]}
            else
              _ -> :error
            end

          [animation_node, point_node | _] ->
            with animation_id when is_integer(animation_id) <-
                   preview_animation_id(animation_node, runtime_model, eval_context),
                 {:ok, [x, y]} <- point_pair_from_node(point_node, runtime_model, eval_context) do
              {:ok, [animation_id, x, y]}
            else
              _ -> :error
            end

          _ ->
            :error
        end
    end
  end

  defp animation_at_args_from_node(_node, _ints, _runtime_model, _eval_context), do: :error

  @spec preview_animation_id(map() | EvalTypes.runtime_value(), map(), map()) :: integer() | nil
  defp preview_animation_id(node, runtime_model, eval_context) do
    eval_view_animation_id(node, Map.put(eval_context, :runtime_model, runtime_model))
  end

  @spec eval_view_animation_id(map() | EvalTypes.runtime_value(), map()) :: integer() | nil
  defp eval_view_animation_id(value, context) do
    case CoreIREvaluator.animation_resource_id_from_value(value, context) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  @spec eval_view_vector_id(map() | EvalTypes.runtime_value(), map()) :: integer() | nil
  defp eval_view_vector_id(value, context)

  defp eval_view_vector_id(%{"type" => "expr", "value" => value}, context),
    do: eval_view_vector_id(value, context)

  defp eval_view_vector_id(%{type: "expr", value: value}, context),
    do: eval_view_vector_id(value, context)

  defp eval_view_vector_id(value, context) do
    case CoreIREvaluator.vector_resource_id_from_value(value, context) do
      {:ok, id} ->
        id

      :error ->
        if is_map(value) and Map.has_key?(value, "type"), do: vector_id_from_view_tree_node(value, context), else: nil
    end
  end

  @spec vector_id_from_view_tree_node(map(), map()) :: integer() | nil
  defp vector_id_from_view_tree_node(node, context) when is_map(node) and is_map(context) do
    indices = Map.get(context, :vector_resource_indices) || %{}
    runtime_model = Map.get(context, :runtime_model) || %{}

    id_from_model = vector_index_from_runtime_model(runtime_model, indices)

    id_from_arg =
      with [arg_node | _] <- ViewTreeEval.node_children(node),
           value when not is_nil(value) <-
             ViewTreeEval.eval_tree_expr_value(arg_node, runtime_model, context) || value_from_runtime_model(runtime_model),
           id when is_integer(id) <- vector_index_for_runtime_value(value, indices) do
        id
      else
        _ -> nil
      end

    id_from_arg || id_from_model
  end

  defp vector_id_from_view_tree_node(_node, _context), do: nil

  @spec preview_vector_id(EvalTypes.runtime_value(), map(), map()) :: integer() | nil
  defp preview_vector_id(vector_node, runtime_model, eval_context)
       when is_map(runtime_model) and is_map(eval_context) do
    indices = Map.get(eval_context, :vector_resource_indices) || %{}

    eval_context =
      if map_size(Map.get(eval_context, :runtime_model) || %{}) > 0,
        do: eval_context,
        else: Map.put(eval_context, :runtime_model, runtime_model)

    id_from_model = vector_index_from_runtime_model(runtime_model, indices)
    id_from_node = eval_view_vector_id(vector_node, eval_context)

    cond do
      is_integer(id_from_model) and vector_preview_prefers_model_scan?(vector_node) ->
        id_from_model

      true ->
        [id_from_model, id_from_node]
        |> Enum.filter(&is_integer/1)
        |> case do
          [] -> nil
          ids -> Enum.min(ids)
        end
    end
  end

  defp preview_vector_id(_vector_node, _runtime_model, _eval_context), do: nil

  @spec vector_preview_prefers_model_scan?(map()) :: boolean()
  defp vector_preview_prefers_model_scan?(node) when is_map(node) do
    type = view_tree_node_type(node)

    type != "" and type not in ["var", "expr", "field", "record", "group"] and
      not String.starts_with?(type, "drawVector")
  end

  defp vector_preview_prefers_model_scan?(_node), do: false

  @spec value_from_runtime_model(map()) :: map() | nil
  defp value_from_runtime_model(runtime_model) when is_map(runtime_model) do
    Enum.find_value(runtime_model, fn
      {_key, %{"ctor" => "Just", "args" => [inner]} = value} when is_map(inner) -> value
      _ -> nil
    end)
  end

  defp value_from_runtime_model(_runtime_model), do: nil

  @spec vector_index_from_runtime_model(map(), map()) :: integer() | nil
  defp vector_index_from_runtime_model(runtime_model, indices)
       when is_map(runtime_model) and is_map(indices) do
    runtime_model
    |> Map.values()
    |> Enum.flat_map(&vector_index_ids_for_runtime_value(&1, indices))
    |> case do
      [] -> nil
      ids -> Enum.min(ids)
    end
  end

  defp vector_index_from_runtime_model(_runtime_model, _indices), do: nil

  @spec vector_index_ids_for_runtime_value(EvalTypes.runtime_value(), map()) :: [integer()]
  defp vector_index_ids_for_runtime_value(%{"ctor" => "Just", "args" => [inner]}, indices),
    do: vector_index_ids_for_runtime_value(inner, indices)

  defp vector_index_ids_for_runtime_value(%{ctor: "Just", args: [inner]}, indices),
    do: vector_index_ids_for_runtime_value(inner, indices)

  defp vector_index_ids_for_runtime_value(%{"ctor" => ctor, "args" => _}, indices) when is_binary(ctor) do
    case vector_index_for_runtime_ctor(ctor, indices) do
      id when is_integer(id) -> [id]
      _ -> []
    end
  end

  defp vector_index_ids_for_runtime_value(%{ctor: ctor, args: _}, indices) when is_binary(ctor) do
    case vector_index_for_runtime_ctor(to_string(ctor), indices) do
      id when is_integer(id) -> [id]
      _ -> []
    end
  end

  defp vector_index_ids_for_runtime_value(_value, _indices), do: []

  @spec vector_index_for_runtime_value(EvalTypes.runtime_value(), map()) :: integer() | nil
  defp vector_index_for_runtime_value(%{"ctor" => "Just", "args" => [inner]}, indices),
    do: vector_index_for_runtime_value(inner, indices)

  defp vector_index_for_runtime_value(%{ctor: "Just", args: [inner]}, indices),
    do: vector_index_for_runtime_value(inner, indices)

  defp vector_index_for_runtime_value(%{"ctor" => ctor, "args" => _}, indices) when is_binary(ctor),
    do: vector_index_for_runtime_ctor(ctor, indices)

  defp vector_index_for_runtime_value(%{ctor: ctor, args: _}, indices) when is_binary(ctor),
    do: vector_index_for_runtime_ctor(to_string(ctor), indices)

  defp vector_index_for_runtime_value(_value, _indices), do: nil

  @spec vector_index_for_runtime_ctor(String.t(), map()) :: integer() | nil
  defp vector_index_for_runtime_ctor(ctor, indices) when is_binary(ctor) and is_map(indices) do
    ctor = to_string(ctor)

    case Map.get(indices, ctor) do
      id when is_integer(id) ->
        id

      _ ->
        indices
        |> Enum.filter(fn {key, _id} -> String.ends_with?(to_string(key), ctor) end)
        |> case do
          [] ->
            nil

          [{_key, id}] ->
            id

          matches ->
            matches
            |> Enum.min_by(fn {key, _id} -> byte_size(to_string(key)) end)
            |> then(fn {_key, id} -> id end)
        end
    end
  end

  defp vector_index_for_runtime_ctor(_ctor, _indices), do: nil

  @spec clear_args_from_node(map(), [integer()], map(), map()) :: SemTypes.draw_args()
  defp clear_args_from_node(node, ints, runtime_model, eval_context)
       when is_map(node) and is_list(ints) and is_map(runtime_model) and is_map(eval_context) do
    case require_ints(ints, 1) do
      {:ok, [color]} ->
        {:ok, [color]}

      :error ->
        case ViewTreeEval.node_children(node) do
          [color_node | _] ->
            case ViewTreeEval.eval_view_color(color_node, runtime_model, eval_context) do
              color when is_integer(color) -> {:ok, [color]}
              _ -> :error
            end

          _ ->
            :error
        end
    end
  end

  defp clear_args_from_node(_node, _ints, _runtime_model, _eval_context), do: :error

  @spec line_args_from_node(map(), [integer()], map(), map()) :: SemTypes.draw_args()
  defp line_args_from_node(node, ints, runtime_model, eval_context)
       when is_map(node) and is_list(ints) and is_map(runtime_model) and is_map(eval_context) do
    case require_ints(ints, 5) do
      {:ok, args} ->
        {:ok, args}

      :error ->
        case ViewTreeEval.node_children(node) do
          [start_node, end_node, color_node | _] ->
            with {:ok, [x1, y1]} <- point_pair_from_node(start_node, runtime_model, eval_context),
                 {:ok, [x2, y2]} <- point_pair_from_node(end_node, runtime_model, eval_context),
                 color when is_integer(color) <-
                   ViewTreeEval.eval_view_color(color_node, runtime_model, eval_context) do
              {:ok, [x1, y1, x2, y2, color]}
            else
              _ -> :error
            end

          _ ->
            :error
        end
    end
  end

  defp line_args_from_node(_node, _ints, _runtime_model, _eval_context), do: :error

  @spec circle_args_from_node(map(), [integer()], map(), map()) :: SemTypes.draw_args()
  defp circle_args_from_node(node, ints, runtime_model, eval_context)
       when is_map(node) and is_list(ints) and is_map(runtime_model) and is_map(eval_context) do
    case require_ints(ints, 4) do
      {:ok, args} ->
        {:ok, args}

      :error ->
        case ViewTreeEval.node_children(node) do
          [center_node, radius_node, color_node | _] ->
            with {:ok, [cx, cy]} <-
                   point_pair_from_node(center_node, runtime_model, eval_context),
                 radius when is_integer(radius) <-
                   ViewTreeEval.eval_view_int(radius_node, runtime_model, eval_context),
                 color when is_integer(color) <-
                   ViewTreeEval.eval_view_color(color_node, runtime_model, eval_context) do
              {:ok, [cx, cy, radius, color]}
            else
              _ -> :error
            end

          _ ->
            :error
        end
    end
  end

  defp circle_args_from_node(_node, _ints, _runtime_model, _eval_context), do: :error

  @spec rect_color_args_from_node(map(), [integer()], map(), map()) :: SemTypes.draw_args()
  defp rect_color_args_from_node(node, ints, runtime_model, eval_context)
       when is_map(node) and is_list(ints) and is_map(runtime_model) and is_map(eval_context) do
    case require_ints(ints, 5) do
      {:ok, args} ->
        {:ok, args}

      :error ->
        case ViewTreeEval.node_children(node) do
          [bounds_node, color_node | _] ->
            with {:ok, [x, y, w, h]} <-
                   rect_quad_from_node(bounds_node, runtime_model, eval_context),
                 color when is_integer(color) <-
                   ViewTreeEval.eval_view_color(color_node, runtime_model, eval_context) do
              {:ok, [x, y, w, h, color]}
            else
              _ -> :error
            end

          _ ->
            :error
        end
    end
  end

  defp rect_color_args_from_node(_node, _ints, _runtime_model, _eval_context), do: :error

  @spec round_rect_args_from_node(map(), [integer()], map(), map()) :: SemTypes.draw_args()
  defp round_rect_args_from_node(node, ints, runtime_model, eval_context)
       when is_map(node) and is_list(ints) and is_map(runtime_model) and is_map(eval_context) do
    case require_ints(ints, 6) do
      {:ok, args} ->
        {:ok, args}

      :error ->
        case ViewTreeEval.node_children(node) do
          [bounds_node, radius_node, color_node | _] ->
            with {:ok, [x, y, w, h]} <-
                   rect_quad_from_node(bounds_node, runtime_model, eval_context),
                 radius when is_integer(radius) <-
                   ViewTreeEval.eval_view_int(radius_node, runtime_model, eval_context),
                 color when is_integer(color) <-
                   ViewTreeEval.eval_view_color(color_node, runtime_model, eval_context) do
              {:ok, [x, y, w, h, radius, color]}
            else
              _ -> :error
            end

          _ ->
            :error
        end
    end
  end

  defp round_rect_args_from_node(_node, _ints, _runtime_model, _eval_context), do: :error

  @spec rect_angle_args_from_node(map(), [integer()], map(), map()) :: SemTypes.draw_args()
  defp rect_angle_args_from_node(node, ints, runtime_model, eval_context)
       when is_map(node) and is_list(ints) and is_map(runtime_model) and is_map(eval_context) do
    case require_ints(ints, 6) do
      {:ok, args} ->
        {:ok, args}

      :error ->
        case ViewTreeEval.node_children(node) do
          [bounds_node, start_node, end_node | _] ->
            with {:ok, [x, y, w, h]} <-
                   rect_quad_from_node(bounds_node, runtime_model, eval_context),
                 start_angle when is_integer(start_angle) <-
                   ViewTreeEval.eval_view_int(start_node, runtime_model, eval_context),
                 end_angle when is_integer(end_angle) <-
                   ViewTreeEval.eval_view_int(end_node, runtime_model, eval_context) do
              {:ok, [x, y, w, h, start_angle, end_angle]}
            else
              _ -> :error
            end

          _ ->
            :error
        end
    end
  end

  defp rect_angle_args_from_node(_node, _ints, _runtime_model, _eval_context), do: :error

  @spec text_int_args_from_node(map(), [integer()], map(), map()) :: SemTypes.draw_args()
  defp text_int_args_from_node(node, ints, runtime_model, eval_context)
       when is_map(node) and is_list(ints) and is_map(runtime_model) and is_map(eval_context) do
    case require_ints(ints, 4) do
      {:ok, args} ->
        {:ok, args}

      :error ->
        case ViewTreeEval.node_children(node) do
          [font_node, pos_node, value_node | _] ->
            with font_id when is_integer(font_id) <-
                   eval_view_font_id(font_node, runtime_model, eval_context),
                 {:ok, [x, y]} <- point_pair_from_node(pos_node, runtime_model, eval_context),
                 value when is_integer(value) <-
                   ViewTreeEval.eval_view_int(value_node, runtime_model, eval_context) do
              {:ok, [font_id, x, y, value]}
            else
              _ -> :error
            end

          _ ->
            :error
        end
    end
  end

  defp text_int_args_from_node(_node, _ints, _runtime_model, _eval_context), do: :error

  @spec text_label_args_from_node(map(), [integer()], map(), map()) :: SemTypes.draw_args_mixed()
  defp text_label_args_from_node(node, ints, runtime_model, eval_context)
       when is_map(node) and is_list(ints) and is_map(runtime_model) and is_map(eval_context) do
    case require_ints(ints, 3) do
      {:ok, args} ->
        {:ok, args}

      :error ->
        case ViewTreeEval.node_children(node) do
          [font_node, pos_node | _] ->
            with font_id when is_integer(font_id) <-
                   eval_view_font_id(font_node, runtime_model, eval_context) do
              case point_pair_from_node(pos_node, runtime_model, eval_context) do
                {:ok, [x, y]} ->
                  {:ok, [font_id, x, y]}

                :error ->
                  pos_ints = node_int_args(pos_node, runtime_model, eval_context)

                  case require_ints(pos_ints, 2) do
                    {:ok, [x, y]} -> {:ok, [font_id, x, y]}
                    :error -> :error
                  end
              end
            else
              _ -> :error
            end

          _ ->
            :error
        end
    end
  end

  defp text_label_args_from_node(_node, _ints, _runtime_model, _eval_context), do: :error

  @spec eval_view_font_id(map(), map(), map()) :: integer() | nil
  defp eval_view_font_id(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    case ViewTreeEval.eval_view_int(node, runtime_model, eval_context) do
      int when is_integer(int) ->
        int

      _ ->
        type =
          node
          |> Map.get("type", Map.get(node, :type, ""))
          |> to_string()
          |> String.downcase()

        label =
          node
          |> Map.get("label", Map.get(node, :label, ""))
          |> to_string()
          |> String.downcase()

        cond do
          String.contains?(type, "defaultfont") -> 1
          String.contains?(type, "uifont") -> 1
          String.contains?(label, "defaultfont") -> 1
          String.contains?(label, "uifont") -> 1
          true -> nil
        end
    end
  end

  defp eval_view_font_id(_node, _runtime_model, _eval_context), do: nil

  @spec rect_quad_from_node(map(), map(), map()) :: SemTypes.draw_args()
  defp rect_quad_from_node(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    type = to_string(node["type"] || node[:type] || "")

    case type do
      "record" ->
        fields =
          node
          |> ViewTreeEval.node_children()
          |> Enum.filter(&(to_string(&1["type"] || &1[:type] || "") == "field"))

        x =
          fields
          |> Enum.find(&(to_string(&1["label"] || &1[:label] || "") == "x"))
          |> ViewTreeEval.field_value_int(runtime_model, eval_context)

        y =
          fields
          |> Enum.find(&(to_string(&1["label"] || &1[:label] || "") == "y"))
          |> ViewTreeEval.field_value_int(runtime_model, eval_context)

        w =
          fields
          |> Enum.find(&(to_string(&1["label"] || &1[:label] || "") == "w"))
          |> ViewTreeEval.field_value_int(runtime_model, eval_context)

        h =
          fields
          |> Enum.find(&(to_string(&1["label"] || &1[:label] || "") == "h"))
          |> ViewTreeEval.field_value_int(runtime_model, eval_context)

        if Enum.all?([x, y, w, h], &is_integer/1), do: {:ok, [x, y, w, h]}, else: :error

      _ ->
        :error
    end
  end

  defp rect_quad_from_node(_node, _runtime_model, _eval_context), do: :error

  @spec path_args_from_node(map(), map(), map()) :: SemTypes.path_args()
  defp path_args_from_node(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    children =
      case node["children"] || node[:children] do
        list when is_list(list) -> Enum.filter(list, &is_map/1)
        _ -> []
      end

    case children do
      [points_node, offset_x_node, offset_y_node, rotation_node | _] ->
        with {:ok, points} <- path_points_from_node(points_node, runtime_model, eval_context),
             offset_x when is_integer(offset_x) <-
               ViewTreeEval.eval_view_int(offset_x_node, runtime_model, eval_context),
             offset_y when is_integer(offset_y) <-
               ViewTreeEval.eval_view_int(offset_y_node, runtime_model, eval_context),
             rotation when is_integer(rotation) <-
               ViewTreeEval.eval_view_int(rotation_node, runtime_model, eval_context) do
          {:ok, %{points: points, offset_x: offset_x, offset_y: offset_y, rotation: rotation}}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp path_args_from_node(_node, _runtime_model, _eval_context), do: :error

  @spec path_points_from_node(map(), map(), map()) :: SemTypes.point_list()
  defp path_points_from_node(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    type = to_string(node["type"] || node[:type] || "")

    cond do
      type == "List" ->
        children =
          case node["children"] || node[:children] do
            list when is_list(list) -> Enum.filter(list, &is_map/1)
            _ -> []
          end

        points =
          children
          |> Enum.map(&point_pair_from_node(&1, runtime_model, eval_context))

        if Enum.all?(points, &match?({:ok, _}, &1)) do
          {:ok, Enum.map(points, fn {:ok, pair} -> pair end)}
        else
          :error
        end

      true ->
        :error
    end
  end

  defp path_points_from_node(_node, _runtime_model, _eval_context), do: :error

  @spec point_pair_from_node(map(), map(), map()) :: SemTypes.point_pair()
  defp point_pair_from_node(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    type = to_string(node["type"] || node[:type] || "")
    op = to_string(node["op"] || node[:op] || "")

    case {type, op} do
      {"tuple2", _} ->
        children =
          case node["children"] || node[:children] do
            list when is_list(list) -> Enum.filter(list, &is_map/1)
            _ -> []
          end

        case children do
          [x_node, y_node | _] ->
            x = ViewTreeEval.eval_view_int(x_node, runtime_model, eval_context)
            y = ViewTreeEval.eval_view_int(y_node, runtime_model, eval_context)
            if is_integer(x) and is_integer(y), do: {:ok, [x, y]}, else: :error

          _ ->
            :error
        end

      {"record", _} ->
        case ViewTreeEval.record_point_coords_from_node(node, runtime_model, eval_context) do
          {:ok, coords} -> {:ok, coords}
          :error -> :error
        end

      {"expr", "record_literal"} ->
        ViewTreeEval.record_point_coords_from_node(node, runtime_model, eval_context)

      {"var", _} ->
        case ViewTreeEval.view_binding_value(ViewTreeEval.view_var_name(node), runtime_model, eval_context)
             |> ViewTreeEval.point_coords_from_value() do
          {:ok, coords} ->
            {:ok, coords}

          :error ->
            screen_center_point(runtime_model)
        end

      _ ->
        :error
    end
  end

  defp point_pair_from_node(_node, _runtime_model, _eval_context), do: :error

  @spec screen_center_point(map()) :: SemTypes.point_pair()
  defp screen_center_point(runtime_model) when is_map(runtime_model) do
    case {model_screen_dimension(runtime_model, "screenW"), model_screen_dimension(runtime_model, "screenH")} do
      {w, h} when is_integer(w) and is_integer(h) -> {:ok, [div(w, 2), div(h, 2)]}
      _ -> :error
    end
  end

  defp screen_center_point(_runtime_model), do: :error

  @spec text_label_from_node(map(), map(), map()) :: String.t()
  defp text_label_from_node(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    field_text = Map.get(node, "text") || Map.get(node, :text)

    child_text =
      case ViewTreeEval.node_children(node) do
        [_font_node, _pos_node, label_node | _] ->
          ViewTreeEval.eval_view_text(label_node, runtime_model, eval_context)

        _ ->
          nil
      end

    cond do
      is_binary(field_text) and String.trim(field_text) != "" ->
        field_text

      is_binary(child_text) and String.trim(child_text) != "" ->
        child_text

      true ->
        label = (node["label"] || node[:label] || "") |> to_string()

        case Regex.run(~r/^\s*-?\d+\s*,\s*-?\d+\s*,\s*(.+)\s*$/, label) do
          [_, text] ->
            text = String.trim(text)
            if byte_size(text) > 0, do: text, else: "Label"

          _ ->
            "Label"
        end
    end
  end

  defp text_label_from_node(_node, _runtime_model, _eval_context), do: "Label"

  @spec text_args_from_node(map(), [integer()], map(), map()) :: SemTypes.draw_args_mixed()
  defp text_args_from_node(node, ints, runtime_model, eval_context)
       when is_map(node) and is_list(ints) and is_map(runtime_model) and is_map(eval_context) do
    case text_box_int_args_from_node(node, ints, runtime_model, eval_context) do
      {:ok, [font_id, x, y, w, h, alignment, overflow]} ->
        field_text = Map.get(node, "text") || Map.get(node, :text)

        if text = ViewTreeEval.normalize_text_value(field_text) do
          {:ok, [font_id, x, y, w, h, alignment, overflow, text]}
        else
          case List.last(ViewTreeEval.node_children(node)) do
            text_node when is_map(text_node) ->
              text =
                ViewTreeEval.eval_view_text(text_node, runtime_model, eval_context) ||
                  text_node
                  |> Map.get("label")
                  |> ViewTreeEval.normalize_text_value() ||
                  ""

              {:ok, [font_id, x, y, w, h, alignment, overflow, text]}

            nil ->
              :error
          end
        end

      :error ->
        :error
    end
  end

  defp text_args_from_node(_node, _ints, _runtime_model, _eval_context), do: :error

  defp text_box_int_args_from_node(node, ints, runtime_model, eval_context)
       when is_map(node) and is_list(ints) and is_map(runtime_model) and is_map(eval_context) do
    case require_ints(ints, 7) do
      {:ok, [font_id, x, y, w, h, alignment, overflow | _]} ->
        {:ok, [font_id, x, y, w, h, alignment, overflow]}

      :error ->
        case require_ints(ints, 5) do
          {:ok, [font_id, x, y, w, h | _]} ->
            alignment =
              text_alignment_value(Map.get(node, "text_align") || Map.get(node, :text_align))

            overflow =
              text_overflow_value(Map.get(node, "text_overflow") || Map.get(node, :text_overflow))

            {:ok, [font_id, x, y, w, h, alignment, overflow]}

          :error ->
            text_int_args_from_children(ViewTreeEval.node_children(node), runtime_model, eval_context)
        end
    end
  end

  defp text_box_int_args_from_node(_node, _ints, _runtime_model, _eval_context), do: :error

  defp text_int_args_from_children(children, runtime_model, eval_context)
       when is_list(children) do
    case children do
      [font_node, options_node, bounds_node, _text_node] ->
        with font_id when is_integer(font_id) <-
               eval_view_font_id(font_node, runtime_model, eval_context),
             {:ok, [x, y, w, h]} <- rect_quad_from_node(bounds_node, runtime_model, eval_context),
             {:ok, [alignment, overflow]} <-
               text_options_from_node(options_node, runtime_model, eval_context) do
          {:ok, [font_id, x, y, w, h, alignment, overflow]}
        else
          _ -> :error
        end

      [font_node, x_node, y_node, w_node, h_node, alignment_node, overflow_node, _text_node | _] ->
        with font_id when is_integer(font_id) <-
               eval_view_font_id(font_node, runtime_model, eval_context),
             x when is_integer(x) <- ViewTreeEval.eval_view_int(x_node, runtime_model, eval_context),
             y when is_integer(y) <- ViewTreeEval.eval_view_int(y_node, runtime_model, eval_context),
             w when is_integer(w) <- ViewTreeEval.eval_view_int(w_node, runtime_model, eval_context),
             h when is_integer(h) <- ViewTreeEval.eval_view_int(h_node, runtime_model, eval_context),
             alignment when is_integer(alignment) <-
               ViewTreeEval.eval_view_int(alignment_node, runtime_model, eval_context),
             overflow when is_integer(overflow) <-
               ViewTreeEval.eval_view_int(overflow_node, runtime_model, eval_context) do
          {:ok, [font_id, x, y, w, h, alignment, overflow]}
        else
          _ -> :error
        end

      [font_node, x_node, y_node, w_node, h_node, _text_node | _] ->
        with font_id when is_integer(font_id) <-
               eval_view_font_id(font_node, runtime_model, eval_context),
             x when is_integer(x) <- ViewTreeEval.eval_view_int(x_node, runtime_model, eval_context),
             y when is_integer(y) <- ViewTreeEval.eval_view_int(y_node, runtime_model, eval_context),
             w when is_integer(w) <- ViewTreeEval.eval_view_int(w_node, runtime_model, eval_context),
             h when is_integer(h) <- ViewTreeEval.eval_view_int(h_node, runtime_model, eval_context) do
          {:ok, [font_id, x, y, w, h, 1, 0]}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp text_int_args_from_children(_children, _runtime_model, _eval_context), do: :error

  defp text_options_from_node(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    type = to_string(node["type"] || node[:type] || "")

    case type do
      "record" ->
        fields =
          node
          |> ViewTreeEval.node_children()
          |> Enum.filter(&(to_string(&1["type"] || &1[:type] || "") == "field"))

        alignment =
          fields
          |> Enum.find(&(to_string(&1["label"] || &1[:label] || "") == "alignment"))
          |> ViewTreeEval.field_value_int(runtime_model, eval_context)

        overflow =
          fields
          |> Enum.find(&(to_string(&1["label"] || &1[:label] || "") == "overflow"))
          |> ViewTreeEval.field_value_int(runtime_model, eval_context)

        if is_integer(alignment) and is_integer(overflow),
          do: {:ok, [alignment, overflow]},
          else: {:ok, [1, 0]}

      _ ->
        {:ok, [1, 0]}
    end
  end

  defp text_options_from_node(_node, _runtime_model, _eval_context), do: {:ok, [1, 0]}

  defp text_alignment_value("left"), do: 0
  defp text_alignment_value("right"), do: 2
  defp text_alignment_value(_), do: 1

  defp text_overflow_value("trailing_ellipsis"), do: 1
  defp text_overflow_value("fill"), do: 2
  defp text_overflow_value(_), do: 0

  defp text_alignment_name(0), do: "left"
  defp text_alignment_name(2), do: "right"
  defp text_alignment_name(_), do: "center"

  defp text_overflow_name(1), do: "trailing_ellipsis"
  defp text_overflow_name(2), do: "fill"
  defp text_overflow_name(_), do: "word_wrap"
end
