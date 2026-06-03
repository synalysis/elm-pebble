defmodule Elmx.Runtime.Executor.View do
  @moduledoc false

  alias Elmx.Runtime.Executor.Model
  alias Elmx.Runtime.ViewOutput
  alias Elmx.Runtime.ViewShape
  alias Elmx.Runtime.Values
  alias Elmx.Types

  @spec safe_view(module(), Types.runtime_model()) :: Types.view_output_tree()
  def safe_view(module, runtime_model) do
    if function_exported?(module, :view, 1) do
      apply(module, :view, [Model.runtime_model_from_elm(runtime_model)])
      |> normalize_view_tree()
    else
      %{type: "empty", children: []}
    end
  rescue
    _ -> %{type: "previewUnavailable", label: "view evaluation failed", children: []}
  end

  @spec preview_rows(
          Types.view_output_tree() | Types.view_shape_input(),
          Types.executor_request(),
          Types.runtime_model()
        ) :: [Types.view_output_row()]
  def preview_rows(tree, request, runtime_model)

  def preview_rows(%{"type" => _} = tree, request, runtime_model),
    do: ViewOutput.from_view_tree(tree, preview_output_opts(request, runtime_model))

  def preview_rows(%{type: type} = tree, request, runtime_model)
      when is_binary(type) or is_atom(type),
      do:
        tree
        |> stringify_view_tree()
        |> Values.wire_value()
        |> ViewOutput.from_view_tree(preview_output_opts(request, runtime_model))

  def preview_rows(_tree, _request, _runtime_model), do: []

  @spec normalize_view_tree(Types.view_shape_input()) :: Types.view_output_tree()
  def normalize_view_tree(tree) do
    tree
    |> ViewShape.normalize()
    |> stringify_view_tree()
  end

  @spec stringify_view_tree(Types.view_shape_input()) :: Types.view_output_tree()
  def stringify_view_tree(%{"type" => type} = node) do
    children =
      (Map.get(node, "children") || [])
      |> Enum.map(&stringify_view_tree/1)

    node
    |> Map.put("type", type)
    |> Map.put("kind", type)
    |> Map.put("children", children)
  end

  def stringify_view_tree(other),
    do: %{"type" => "node", "kind" => "node", "label" => inspect(other), "children" => []}

  @spec preview_output_opts(Types.executor_request(), Types.runtime_model()) ::
          Types.view_output_opts()
  def preview_output_opts(request, runtime_model) when is_map(request) and is_map(runtime_model) do
    [
      vector_resource_indices: resource_indices(request, :vector_resource_indices),
      bitmap_resource_indices: resource_indices(request, :bitmap_resource_indices),
      animation_resource_indices: resource_indices(request, :animation_resource_indices),
      screen_w: screen_dimension(runtime_model, "screenW"),
      screen_h: screen_dimension(runtime_model, "screenH"),
      runtime_model: runtime_model
    ]
  end

  @spec resource_indices(Types.executor_request(), atom()) :: %{String.t() => pos_integer()}
  def resource_indices(request, key) when is_map(request) do
    Map.get(request, key) || Map.get(request, Atom.to_string(key)) || %{}
  end

  @spec screen_dimension(Types.runtime_model(), String.t()) :: pos_integer() | nil
  def screen_dimension(model, key) when is_map(model) do
    case Map.get(model, key) || Map.get(model, String.to_atom(key)) do
      n when is_integer(n) and n > 0 -> n
      n when is_float(n) -> trunc(n)
      _ -> nil
    end
  end
end
