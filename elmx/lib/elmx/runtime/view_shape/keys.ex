defmodule Elmx.Runtime.ViewShape.Keys do
  @moduledoc false
  alias Elmx.Types, as: Types

  @spec stringify_keys(map() | list() | Types.elm_value()) :: Types.elm_value()

  def stringify_keys(map) when is_map(map) do
    map
    |> Enum.map(fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_keys(v)}
      {k, v} -> {to_string(k), stringify_keys(v)}
    end)
    |> Map.new()
  end

  def stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  def stringify_keys(other), do: other

end
