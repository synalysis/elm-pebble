defmodule Elmx.Runtime.ViewShape do
  @moduledoc """
  Coerces Elm ADT view values (ctor maps / tagged tuples) into debugger preview maps.

  Used for functions compiled from Elm source (including `Pebble.Ui.*` helpers and
  user-defined wrappers) without name-specific codegen hooks.
  """

  alias Elmx.Runtime.ViewShape.{Coerce, Keys, RenderOps}
  alias Elmx.Types

  @pebble_ui_node_tags %{
    1000 => "WindowStack",
    1001 => "WindowNode",
    1002 => "CanvasLayer"
  }

  @spec normalize(Types.view_shape_input()) :: Types.view_output_tree()
  def normalize(term) do
    case coerce(term) do
      %{"type" => _} = node ->
        node

      %{type: type} = node when is_binary(type) or is_atom(type) ->
        Keys.stringify_keys(node)

      ops when is_list(ops) ->
        case RenderOps.normalize_render_op_list(ops) do
          {:ok, tree} -> tree
          :error -> %{"type" => "node", "label" => inspect(ops), "children" => []}
        end

      other ->
        %{"type" => "node", "label" => inspect(other), "children" => []}
    end
  end

  @spec coerce(Types.view_shape_input()) :: Types.view_shape_coerce_result()
  def coerce(%{"type" => _} = node), do: Keys.stringify_keys(node)
  def coerce(%{type: _} = node), do: Keys.stringify_keys(node)

  def coerce(%{"ctor" => ctor, "args" => args}) when is_binary(ctor) and is_list(args),
    do: Coerce.coerce_ctor(ctor, Enum.map(args, &coerce/1))

  def coerce({ctor, args}) when is_atom(ctor) and is_list(args),
    do: Coerce.coerce_ctor(Atom.to_string(ctor), Enum.map(args, &coerce/1))

  def coerce({tag, payload}) when is_integer(tag) do
    case Map.get(@pebble_ui_node_tags, tag) do
      nil ->
        nil

      "WindowStack" ->
        Coerce.coerce_ctor("WindowStack", tagged_ctor_args(payload))

      ctor ->
        Coerce.coerce_ctor(ctor, tagged_ctor_args(payload))
    end
  end

  def coerce(tuple) when is_tuple(tuple) do
    case Tuple.to_list(tuple) do
      [ctor | args] when is_atom(ctor) ->
        Coerce.coerce_ctor(Atom.to_string(ctor), Enum.map(args, &coerce/1))

      _ ->
        tuple
    end
  end

  def coerce(list) when is_list(list), do: Enum.map(list, &coerce/1)
  def coerce(other), do: other

  defp tagged_ctor_args({left, right}), do: [coerce(left), coerce(right)]
  defp tagged_ctor_args(list) when is_list(list), do: Enum.map(list, &coerce/1)
  defp tagged_ctor_args(other), do: [coerce(other)]
end
