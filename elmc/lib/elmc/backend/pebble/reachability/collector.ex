defmodule Elmc.Backend.Pebble.Reachability.Collector do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Types, as: CCodegenTypes
  alias Elmc.Backend.Pebble.Types

  @spec collect(CCodegenTypes.ir_expr() | list() | nil | String.t() | number() | atom()) ::
          Types.call_target_list()
  def collect(nil), do: []
  def collect(value) when is_binary(value), do: []
  def collect(value) when is_number(value), do: []
  def collect(value) when is_atom(value), do: []

  def collect(list) when is_list(list) do
    Enum.flat_map(list, &collect/1)
  end

  def collect(%{op: op, target: target} = expr)
      when op in [:qualified_call, :qualified_call1, :constructor_call] and is_binary(target) do
    [target | collect(Map.values(expr))]
  end

  def collect(%{op: op, name: name} = expr)
      when op in [:call, :call1] and is_binary(name) do
    [name | collect(Map.values(expr))]
  end

  def collect(%{op: :var, name: name} = expr) when is_binary(name) do
    [name | collect(Map.delete(expr, :name))]
  end

  def collect(map) when is_map(map) do
    map
    |> Map.values()
    |> Enum.flat_map(&collect/1)
  end
end
