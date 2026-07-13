defmodule Elmx.Runtime.ViewOutput.Draw do
  @moduledoc false

  alias Elmx.Types
  alias Elmx.Runtime.ViewOutput.Draw.{Assets, Path, Shapes, Text}

  @type opts :: Types.view_output_opts()

  @spec draw_row(Types.view_draw_node(), opts()) :: Types.view_output_row() | nil
  def draw_row(node, opts) when is_map(node),
    do: node |> normalize_node_type() |> do_draw_row(opts)

  @spec normalize_node_type(Types.view_draw_node()) :: Types.view_draw_node()
  def normalize_node_type(node) when is_map(node) do
    type =
      node
      |> Map.get("type", Map.get(node, :type))
      |> to_string()

    node
    |> Map.new(fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
    |> Map.put("type", type)
  end

  @spec do_draw_row(Types.view_draw_node(), opts()) :: Types.view_output_row() | nil
  def do_draw_row(node, opts) do
    Shapes.row(node, opts) ||
      Assets.row(node, opts) ||
      Text.row(node, opts) ||
      Path.row(node, opts)
  end
end
