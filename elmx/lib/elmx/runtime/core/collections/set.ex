defmodule Elmx.Runtime.Core.Collections.Set do
  @moduledoc false

  alias Elmx.Runtime.Core
  alias Elmx.Types

  @type set :: Types.elm_set()

  defp wrap(items) when is_list(items), do: {:elmx_set, items}
  defp unwrap({:elmx_set, items}) when is_list(items), do: items
  defp unwrap(items) when is_list(items), do: items

  @spec set_empty() :: set()
  def set_empty, do: wrap([])

  def set_from_list(items) when is_list(items), do: wrap(Enum.uniq(items))

  @spec set_insert(Types.elm_value(), set()) :: set()
  def set_insert(value, set) do
    items = unwrap(set)

    if value in items, do: wrap(items), else: wrap([value | items])
  end

  @spec set_member(Types.elm_value(), set()) :: boolean()
  def set_member(value, set), do: value in unwrap(set)

  @spec set_size(set()) :: integer()
  def set_size(set), do: length(unwrap(set))

  @spec set_remove(Types.elm_value(), set()) :: set()
  def set_remove(value, set), do: wrap(Enum.reject(unwrap(set), &(&1 == value)))

  @spec set_is_empty(set()) :: boolean()
  def set_is_empty(set), do: unwrap(set) == []

  @spec set_singleton(Types.elm_value()) :: set()
  def set_singleton(value), do: wrap([value])

  @spec set_to_list(set()) :: list()
  def set_to_list(set) do
    unwrap(set)
    |> Enum.sort(fn ka, kb ->
      case Core.basics_compare(ka, kb) do
        :LT -> true
        _ -> false
      end
    end)
  end

  @spec set_union(set(), set()) :: set()
  def set_union(left, right), do: wrap(Enum.uniq(unwrap(left) ++ unwrap(right)))

  @spec set_intersect(set(), set()) :: set()
  def set_intersect(left, right), do: wrap(Enum.filter(unwrap(left), &(&1 in unwrap(right))))

  @spec set_diff(set(), set()) :: set()
  def set_diff(left, right), do: wrap(Enum.reject(unwrap(left), &(&1 in unwrap(right))))

  @spec set_map(Types.elm_hof(), set()) :: set()
  def set_map(fun, set), do: wrap(Enum.map(unwrap(set), &Core.apply1(fun, &1)))

  @spec set_foldl(Types.elm_hof(), Types.fold_acc(), set()) :: set()
  def set_foldl(fun, acc, set),
    do: Enum.reduce(unwrap(set), acc, fn item, acc0 -> Core.apply2(fun, item, acc0) end)

  @spec set_foldr(Types.elm_hof(), Types.fold_acc(), set()) :: set()
  def set_foldr(fun, acc, set),
    do: Enum.reduce(Enum.reverse(unwrap(set)), acc, fn item, acc0 -> Core.apply2(fun, item, acc0) end)

  @spec set_filter(Types.elm_hof(), set()) :: set()
  def set_filter(fun, set), do: wrap(Enum.filter(unwrap(set), &Core.apply1(fun, &1)))

  @spec set_partition(Types.elm_hof(), set()) :: {set(), set()}
  def set_partition(fun, set) do
    {yes, no} = Enum.split_with(unwrap(set), &Core.apply1(fun, &1))
    {wrap(yes), wrap(no)}
  end
end
