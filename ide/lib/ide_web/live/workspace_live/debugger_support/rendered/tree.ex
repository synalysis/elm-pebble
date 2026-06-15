defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Rendered.Tree do
  @moduledoc false
  @dialyzer :no_match

  alias Ide.Debugger.RuntimeArtifacts
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Rendered.{Normalize, ViewOutput}

  @type view_tree :: Types.view_tree()
  @type model_map :: Types.model_map()
  @type elm_introspect :: Types.elm_introspect()
  @type runtime_input :: Types.runtime_input()

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
        |> Normalize.tree_or_nil()

      _ ->
        ei = RuntimeArtifacts.require_introspect(model)

        model
        |> parser_view_tree()
        |> discard_parser_expression_view_tree(ei)
        |> Normalize.tree_or_nil()
    end
  end

  def rendered_tree(_runtime), do: nil

  @spec runtime_rendered_tree(Ide.Debugger.Types.execution_model(), model_map()) ::
          view_tree() | nil
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

    output_tree = ViewOutput.tree(Map.put(model, "runtime_view_output", refreshed_rows))

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

  @spec concrete_rendered_view_tree?(view_tree(), elm_introspect()) :: boolean()
  defp concrete_rendered_view_tree?(%{"type" => "tuple2"} = tree, _ei),
    do: match?({:ok, _node}, Normalize.ui_value(tree))

  defp concrete_rendered_view_tree?(tree, ei) when is_map(tree) and map_size(tree) > 0 do
    not Ide.Debugger.StepExecution.placeholder_view_tree?(tree) and
      not parser_expression_view_tree?(tree, ei)
  end

  defp concrete_rendered_view_tree?(_tree, _ei), do: false

  @spec discard_parser_expression_view_tree(view_tree(), elm_introspect()) :: view_tree() | nil
  defp discard_parser_expression_view_tree(tree, ei) when is_map(tree) do
    if parser_expression_view_tree?(tree, ei), do: nil, else: tree
  end

  defp discard_parser_expression_view_tree(_tree, _ei), do: nil

  @spec parser_expression_view_tree?(view_tree(), elm_introspect()) :: boolean()
  defp parser_expression_view_tree?(%{"type" => "tuple2"} = tree, _ei),
    do: not match?({:ok, _node}, Normalize.ui_value(tree))

  defp parser_expression_view_tree?(tree, ei) when is_map(tree) and is_map(ei),
    do: ElmEx.DebuggerContract.parser_expression_view_tree_node?(tree, ei)

  defp parser_expression_view_tree?(_tree, _ei), do: false

  @spec reject_placeholder_rendered_tree(view_tree() | nil) :: view_tree() | nil
  defp reject_placeholder_rendered_tree(tree) do
    if Ide.Debugger.StepExecution.placeholder_view_tree?(tree), do: nil, else: tree
  end

  @spec runtime_model(runtime_input()) :: model_map()
  defp runtime_model(%{} = runtime) do
    case Map.get(runtime, :model) || Map.get(runtime, "model") do
      model when is_map(model) -> model
      _ -> %{}
    end
  end

  @spec parser_view_tree(model_map()) :: view_tree() | nil
  defp parser_view_tree(%{} = model) do
    case RuntimeArtifacts.introspect(model) do
      ei when is_map(ei) ->
        tree = Map.get(ei, "view_tree") || Map.get(ei, :view_tree)
        if is_map(tree), do: tree, else: nil

      _ ->
        nil
    end
  end
end
