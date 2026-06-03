defmodule Elmx.Runtime.Core.Collections.Set do
  @moduledoc false

  alias Elmx.Runtime.Core
  alias Elmx.Types

  @type set :: Types.elm_set()

  def set_from_list(items) when is_list(items), do: Enum.uniq(items)

  @spec set_insert(term(), set()) :: set()
  def set_insert(value, set) when is_list(set) do
    if value in set, do: set, else: [value | set]
  end

  @spec set_member(term(), set()) :: boolean()
  def set_member(value, set) when is_list(set), do: value in set

  @spec set_size(set()) :: integer()
  def set_size(set) when is_list(set), do: length(set)

  @spec set_remove(term(), set()) :: set()
  def set_remove(value, set), do: Enum.reject(set, &(&1 == value))

  @spec set_is_empty(set()) :: boolean()
  def set_is_empty(set), do: set == []

  @spec set_singleton(term()) :: set()
  def set_singleton(value), do: [value]

  @spec set_to_list(set()) :: list()
  def set_to_list(set), do: set

  @spec set_union(set(), set()) :: set()
  def set_union(left, right), do: Enum.uniq(left ++ right)

  @spec set_intersect(set(), set()) :: set()
  def set_intersect(left, right), do: Enum.filter(left, &(&1 in right))

  @spec set_diff(set(), set()) :: set()
  def set_diff(left, right), do: Enum.reject(left, &(&1 in right))

  @spec set_map(term(), set()) :: set()
  def set_map(fun, set), do: Enum.map(set, &Core.apply1(fun, &1))

  @spec set_foldl(term(), term(), set()) :: term()
  def set_foldl(fun, acc, set), do: Enum.reduce(set, acc, fn item, acc0 -> Core.apply2(fun, item, acc0) end)

  @spec set_foldr(term(), term(), set()) :: term()
  def set_foldr(fun, acc, set),
    do: Enum.reduce(Enum.reverse(set), acc, fn item, acc0 -> Core.apply2(fun, item, acc0) end)

  @spec set_filter(term(), set()) :: set()
  def set_filter(fun, set), do: Enum.filter(set, &Core.apply1(fun, &1))

  @spec set_partition(term(), set()) :: {set(), set()}
  def set_partition(fun, set), do: Enum.split_with(set, &Core.apply1(fun, &1))
end
