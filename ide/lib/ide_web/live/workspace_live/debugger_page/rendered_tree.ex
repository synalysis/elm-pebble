defmodule IdeWeb.WorkspaceLive.DebuggerPage.RenderedTree do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: SupportTypes

  @type view_node :: SupportTypes.view_node()
  @type rendered_child_row :: %{
          required(:node) => view_node(),
          required(:arg_name) => String.t() | nil,
          required(:path) => String.t()
        }

  @hidden_node_types ~w(debuggerRenderStep elmcRuntimeStep)

  @spec hidden_node_type?(String.t()) :: boolean()
  def hidden_node_type?(type) when is_binary(type), do: type in @hidden_node_types
  def hidden_node_type?(_), do: false

  @spec source_tooltip(view_node()) :: String.t() | nil
  def source_tooltip(node) when is_map(node) do
    source = Map.get(node, "source") || Map.get(node, :source)

    with %{} <- source,
         call when is_binary(call) and call != "" <-
           Map.get(source, "call") || Map.get(source, :call) ||
             Map.get(node, "qualified_target") || Map.get(node, :qualified_target) ||
             tooltip_call(node),
         path when is_binary(path) and path != "" <-
           Map.get(source, "path") || Map.get(source, :path),
         line when is_integer(line) <- Map.get(source, "line") || Map.get(source, :line) do
      "#{call} at #{path}:#{line}"
    else
      _ -> nil
    end
  end

  @spec child_rows([view_node()], view_node(), String.t()) :: [rendered_child_row()]
  def child_rows(children, parent, parent_path)
      when is_list(children) and is_map(parent) and is_binary(parent_path) do
    arg_names = arg_names(parent, length(children))

    children
    |> Enum.with_index()
    |> Enum.map(fn {child, index} ->
      %{node: child, arg_name: Enum.at(arg_names, index), path: "#{parent_path}.#{index}"}
    end)
  end

  @spec arg_names(view_node(), non_neg_integer()) :: [String.t()]
  def arg_names(parent, child_count) when is_map(parent) and is_integer(child_count) do
    explicit = Map.get(parent, "arg_names") || Map.get(parent, :arg_names) || []

    if explicit != [] do
      explicit
    else
      []
    end
  end

  @spec tooltip_call(view_node()) :: String.t() | nil
  defp tooltip_call(node) when is_map(node) do
    type = Map.get(node, "type") || Map.get(node, :type)
    if is_binary(type) and type != "", do: "Ui.#{type}", else: nil
  end
end
