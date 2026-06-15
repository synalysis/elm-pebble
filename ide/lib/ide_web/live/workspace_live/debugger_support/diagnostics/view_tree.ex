defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Diagnostics.ViewTree do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types

  @type view_tree :: Types.view_tree()
  @type wire_value :: Types.wire_value()
  @type execution_model :: Types.execution_model()

  @spec outline(execution_model()) :: String.t()
  def outline(nil), do: "(no snapshot)"

  def outline(runtime) when is_map(runtime) do
    tree = Map.get(runtime, :view_tree) || Map.get(runtime, "view_tree")

    case tree do
      nil -> "(no view tree in snapshot)"
      node -> format_node(node, 0) |> String.trim_trailing()
    end
  end

  def outline(_), do: "(no snapshot)"

  @spec format_node(view_tree() | wire_value(), non_neg_integer()) :: String.t()
  defp format_node(node, depth) when is_map(node) do
    indent = String.duplicate("  ", depth)
    type = Map.get(node, :type) || Map.get(node, "type") || "node"
    line = "#{indent}- #{type}\n"
    children = Map.get(node, :children) || Map.get(node, "children") || []

    child_lines =
      if is_list(children) do
        children
        |> Enum.map(fn
          child when is_map(child) -> format_node(child, depth + 1)
          other -> "#{indent}  - #{inspect(other)}\n"
        end)
        |> Enum.join("")
      else
        ""
      end

    line <> child_lines
  end

  defp format_node(other, depth) do
    indent = String.duplicate("  ", depth)
    "#{indent}- #{inspect(other)}\n"
  end
end
