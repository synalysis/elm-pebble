defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Rendered.Normalize do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Rendered.Expr
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Rendered.Normalize.Args
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types

  @type rendered_node :: Types.rendered_node()
  @type view_tree :: Types.view_tree()
  @type runtime_value :: Types.runtime_value()

  @spec tree_or_nil(view_tree() | nil) :: view_tree() | nil
  def tree_or_nil(tree), do: normalize_rendered_tree_or_nil(tree)

  @spec ui_value(runtime_value()) :: {:ok, rendered_node()} | :error
  def ui_value(value), do: normalize_rendered_ui_value(value)

  @spec node_arg_fields(String.t() | atom()) :: [String.t()]
  def node_arg_fields(type), do: Args.fields(type)

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

  @spec normalize_rendered_ui_value(Types.runtime_value()) :: {:ok, rendered_node()} | :error
  defp normalize_rendered_ui_value(%{"type" => type, "children" => children} = value)
       when is_binary(type) and is_list(children) and type not in ["tuple2", "List"] do
    value =
      value
      |> Map.put("children", Enum.map(children, &normalize_rendered_child/1))
      |> Args.text_field()
      |> Args.promote()

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

  @spec normalize_rendered_window_node(Types.runtime_value()) :: {:ok, rendered_node()} | :error
  defp normalize_rendered_window_node(value) do
    with {:ok, tag, payload} when tag in [1, 1001] <- normalized_tagged_tuple(value),
         {:ok, [id, layers]} <- Expr.payload_args(payload, 2),
         {:ok, layers} <- normalized_list_values(layers),
         {:ok, layer_nodes} <- normalize_rendered_list(layers, &normalize_rendered_layer_node/1) do
      {:ok,
       %{
         "type" => "window",
         "label" => "",
         "id" => Expr.expr_scalar(normalize_rendered_child(id)),
         "children" => layer_nodes
       }}
    else
      _ -> :error
    end
  end

  @spec normalize_rendered_layer_node(Types.runtime_value()) :: {:ok, rendered_node()} | :error
  defp normalize_rendered_layer_node(value) do
    with {:ok, tag, payload} when tag in [1, 1002] <- normalized_tagged_tuple(value),
         {:ok, [id, ops]} <- Expr.payload_args(payload, 2),
         {:ok, ops} <- normalized_list_values(ops),
         {:ok, op_nodes} <- normalize_rendered_list(ops, &normalize_rendered_op_node/1) do
      {:ok,
       %{
         "type" => "canvasLayer",
         "label" => "",
         "id" => Expr.expr_scalar(normalize_rendered_child(id)),
         "children" => op_nodes
       }}
    else
      _ -> :error
    end
  end

  @spec normalize_rendered_op_node(Types.runtime_value()) :: {:ok, rendered_node()} | :error
  defp normalize_rendered_op_node(%{} = value), do: normalize_rendered_ui_value(value)
  defp normalize_rendered_op_node(_value), do: :error

  @spec normalize_rendered_child(Types.runtime_value()) :: Types.runtime_value()
  defp normalize_rendered_child(%{"type" => _type} = value), do: normalize_rendered_tree(value)
  defp normalize_rendered_child(value), do: value

  @spec normalize_rendered_list(
          [runtime_value()],
          (runtime_value() -> {:ok, rendered_node()} | :error)
        ) ::
          {:ok, [rendered_node()]} | :error
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
end
