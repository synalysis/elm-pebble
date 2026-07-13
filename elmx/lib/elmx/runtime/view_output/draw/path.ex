defmodule Elmx.Runtime.ViewOutput.Draw.Path do
  @moduledoc false

  alias Elmx.Types
  alias Elmx.Runtime.ViewOutput.Geometry

  @type opts :: Types.view_output_opts()

  @path_types ~w(pathFilled pathOutline pathOutlineOpen)

  @spec row(Types.view_draw_node(), opts()) :: Types.view_output_row() | nil
  def row(%{"type" => type} = node, _opts) when type in @path_types do
    path = Map.get(node, "path") || Map.get(node, :path) || node

    case Geometry.path_fields(path) do
      %{"points" => [_ | _]} = fields ->
        Map.put(fields, "kind", Geometry.path_output_kind(type))

      _ ->
        nil
    end
  end

  def row(_node, _opts), do: nil
end
