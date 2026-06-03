defmodule Elmx.Runtime.ViewOutput do
  @moduledoc """
  Flattens evaluated `Pebble.Ui` view trees into debugger `runtime_view_output` rows.
  """

  alias Elmx.Types
  alias Elmx.Runtime.ViewOutput.{Resources, Tree}

  @type opts :: Types.view_output_opts()

  @spec from_view_tree(Types.view_shape_input(), opts()) :: [Types.view_output_row()]
  def from_view_tree(tree, opts \\ []) do
    tree
    |> List.wrap()
    |> Enum.flat_map(&Tree.flatten_node(&1, opts))
    |> Resources.apply_resource_indices(opts)
  end

  @doc """
  Resolves `vector_id` / `animation_id` on flattened rows using optional resource index maps.
  """
  @spec apply_resource_indices([Types.view_output_row()], opts()) :: [Types.view_output_row()]
  defdelegate apply_resource_indices(rows, opts \\ []), to: Resources
end
