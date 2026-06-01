defmodule Elmx.Runtime.Core.Collections do
  @moduledoc false

  alias Elmx.Runtime.Core

  @type dict :: [{integer(), term()}]
  @type set :: [term()]

  @spec dict_from_list(list()) :: dict()
  def dict_from_list(pairs) when is_list(pairs) do
    Enum.reduce(pairs, [], fn pair, acc ->
      case normalize_pair(pair) do
        {key, value} when is_integer(key) -> dict_insert(key, value, acc)
        _ -> acc
      end
    end)
  end

  @spec dict_insert(integer(), term(), dict()) :: dict()
  def dict_insert(key, value, dict) when is_integer(key) and is_list(dict) do
    dict = Enum.reject(dict, fn {k, _} -> k == key end)
    [{key, value} | dict]
  end

  @spec dict_get(integer(), dict()) :: term()
  def dict_get(key, dict) when is_integer(key) do
    case Enum.find(dict, fn {k, _} -> k == key end) do
      {_, value} -> {:Just, value}
      _ -> :Nothing
    end
  end

  @spec dict_get_with_default_int(integer(), integer(), dict()) :: integer()
  def dict_get_with_default_int(default, key, dict) when is_integer(default) and is_integer(key) do
    case dict_get(key, dict) do
      {:Just, value} -> to_int(value, default)
      _ -> default
    end
  end

  @spec dict_member(integer(), dict()) :: boolean()
  def dict_member(key, dict) when is_integer(key),
    do: Enum.any?(dict, fn {k, _} -> k == key end)

  @spec dict_size(dict()) :: integer()
  def dict_size(dict) when is_list(dict), do: length(dict)

  @spec dict_remove(integer(), dict()) :: dict()
  def dict_remove(key, dict) when is_integer(key),
    do: Enum.reject(dict, fn {k, _} -> k == key end)

  @spec dict_is_empty(dict()) :: boolean()
  def dict_is_empty(dict), do: dict == []

  @spec dict_singleton(integer(), term()) :: dict()
  def dict_singleton(key, value) when is_integer(key), do: [{key, value}]

  @spec dict_keys(dict()) :: list()
  def dict_keys(dict), do: Enum.map(dict, fn {k, _} -> k end)

  @spec dict_values(dict()) :: list()
  def dict_values(dict), do: Enum.map(dict, fn {_, v} -> v end)

  @spec dict_to_list(dict()) :: list()
  def dict_to_list(dict), do: Enum.map(dict, fn {k, v} -> {k, v} end)

  @spec dict_map(term(), dict()) :: dict()
  def dict_map(fun, dict) when is_list(dict) do
    Enum.map(dict, fn {k, v} -> {k, Core.apply2(fun, k, v)} end)
  end

  @spec dict_foldl(term(), term(), dict()) :: term()
  def dict_foldl(fun, acc, dict) when is_list(dict) do
    Enum.reduce(dict, acc, fn {k, v}, acc0 -> Core.apply3(fun, k, v, acc0) end)
  end

  @spec dict_foldr(term(), term(), dict()) :: term()
  def dict_foldr(fun, acc, dict) when is_list(dict) do
    Enum.reduce(Enum.reverse(dict), acc, fn {k, v}, acc0 -> Core.apply3(fun, k, v, acc0) end)
  end

  @spec dict_filter(term(), dict()) :: dict()
  def dict_filter(fun, dict) when is_list(dict) do
    Enum.filter(dict, fn {k, v} -> Core.apply2(fun, k, v) end)
  end

  @spec dict_partition(term(), dict()) :: {dict(), dict()}
  def dict_partition(fun, dict) when is_list(dict) do
    Enum.split_with(dict, fn {k, v} -> Core.apply2(fun, k, v) end)
  end

  @spec dict_union(dict(), dict()) :: dict()
  def dict_union(left, right) when is_list(left) and is_list(right) do
    Enum.reduce(right, left, fn {k, v}, acc -> dict_insert(k, v, acc) end)
  end

  @spec dict_intersect(dict(), dict()) :: dict()
  def dict_intersect(left, right) when is_list(left) and is_list(right) do
    right_map = Map.new(right)

    left
    |> Enum.filter(fn {k, _} -> Map.has_key?(right_map, k) end)
    |> Enum.map(fn {k, _} -> {k, Map.fetch!(right_map, k)} end)
  end

  @spec dict_diff(dict(), dict()) :: dict()
  def dict_diff(left, right) when is_list(left) and is_list(right) do
    right_keys = MapSet.new(Enum.map(right, fn {k, _} -> k end))
    Enum.reject(left, fn {k, _} -> MapSet.member?(right_keys, k) end)
  end

  @spec dict_merge(term(), term(), term(), dict(), dict(), term()) :: term()
  def dict_merge(left_step, both_step, right_step, left, right, result)
      when is_list(left) and is_list(right) do
    keys =
      (dict_keys(left) ++ dict_keys(right))
      |> Enum.uniq()
      |> Enum.sort()

    Enum.reduce(keys, result, fn key, acc ->
      in_left = dict_member(key, left)
      in_right = dict_member(key, right)

      cond do
        in_left and in_right ->
          Core.apply4(
            both_step,
            key,
            dict_fetch!(key, left),
            dict_fetch!(key, right),
            acc
          )

        in_left ->
          Core.apply3(left_step, key, dict_fetch!(key, left), acc)

        true ->
          Core.apply3(right_step, key, dict_fetch!(key, right), acc)
      end
    end)
  end

  @spec dict_merge(term(), term(), term(), dict(), dict()) :: term()
  def dict_merge(left_step, both_step, right_step, left, right)
      when is_list(left) and is_list(right) do
    dict_merge(left_step, both_step, right_step, left, right, [])
  end

  @spec dict_update(integer(), term(), dict()) :: dict()
  def dict_update(key, alter, dict) when is_integer(key) do
    current =
      case dict_get(key, dict) do
        {:Just, value} -> {:Just, value}
        :Nothing -> :Nothing
      end

    case Core.apply1(alter, current) do
      {:Just, value} -> dict_insert(key, value, dict)
      %{"ctor" => "Just", "args" => [value]} -> dict_insert(key, value, dict)
      %{ctor: :Just, args: [value]} -> dict_insert(key, value, dict)
      :Nothing -> dict_remove(key, dict)
      %{"ctor" => "Nothing"} -> dict_remove(key, dict)
      %{ctor: :Nothing} -> dict_remove(key, dict)
      other ->
        raise ArgumentError, "dict_update expected Maybe result, got: #{inspect(other)}"
    end
  end

  @spec set_from_list(list()) :: set()
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

  @spec array_empty() :: list()
  def array_empty, do: []

  @spec array_from_list(list()) :: list()
  def array_from_list(items) when is_list(items), do: items

  @spec array_length(list()) :: integer()
  def array_length(array) when is_list(array), do: length(array)

  @spec array_get(integer(), list()) :: term()
  def array_get(index, _array) when is_integer(index) and index < 0, do: :Nothing

  def array_get(index, array) when is_integer(index) and is_list(array) do
    case Enum.at(array, index) do
      nil -> :Nothing
      value -> {:Just, value}
    end
  end

  @spec array_get_with_default_int(integer(), integer(), list()) :: integer()
  def array_get_with_default_int(default, index, array)
      when is_integer(default) and is_integer(index) do
    case array_get(index, array) do
      {:Just, value} -> to_int(value, default)
      _ -> default
    end
  end

  @spec array_set(integer(), term(), list()) :: list()
  def array_set(index, value, array) when is_integer(index) and is_list(array) do
    if index < 0 or index >= length(array) do
      array
    else
      List.replace_at(array, index, value)
    end
  end

  @spec array_push(term(), list()) :: list()
  def array_push(value, array) when is_list(array), do: array ++ [value]

  @spec array_repeat(integer(), term()) :: list()
  def array_repeat(n, value) when is_integer(n), do: List.duplicate(value, max(n, 0))

  @spec array_initialize(integer(), term()) :: list()
  def array_initialize(n, value) when is_integer(n), do: List.duplicate(value, max(n, 0))

  @spec array_is_empty(list()) :: boolean()
  def array_is_empty(array), do: array == []

  @spec array_to_list(list()) :: list()
  def array_to_list(array), do: array

  @spec array_to_indexed_list(list()) :: list()
  def array_to_indexed_list(array), do: Enum.with_index(array)

  @spec array_map(term(), list()) :: list()
  def array_map(fun, array), do: Core.map(fun, array)

  @spec array_indexed_map(term(), list()) :: list()
  def array_indexed_map(fun, array), do: Core.indexed_map(fun, array)

  @spec array_foldl(term(), term(), list()) :: term()
  def array_foldl(fun, acc, array), do: Core.foldl(fun, acc, array)

  @spec array_foldr(term(), term(), list()) :: term()
  def array_foldr(fun, acc, array), do: Core.foldr(fun, acc, array)

  @spec array_filter(term(), list()) :: list()
  def array_filter(fun, array), do: Core.filter(fun, array)

  @spec array_append(list(), list()) :: list()
  def array_append(left, right), do: left ++ right

  @spec array_slice(integer(), integer(), list()) :: list()
  def array_slice(start, length, array) when is_integer(start) and is_integer(length) do
    array |> Enum.drop(start) |> Enum.take(length)
  end

  defp dict_fetch!(key, dict) when is_integer(key) do
    case Enum.find(dict, fn {k, _} -> k == key end) do
      {_, value} -> value
      nil -> raise ArgumentError, "dict_fetch! missing key #{inspect(key)}"
    end
  end

  defp normalize_pair({a, b}), do: {to_int(a, 0), b}
  defp normalize_pair([a, b]), do: {to_int(a, 0), b}
  defp normalize_pair(%{"ctor" => "Tuple", "args" => [a, b]}), do: {to_int(a, 0), b}
  defp normalize_pair(%{ctor: :Tuple, args: [a, b]}), do: {to_int(a, 0), b}
  defp normalize_pair(_), do: {0, nil}

  defp to_int(n, _default) when is_integer(n), do: n

  defp to_int(n, _default) when is_float(n), do: trunc(n)

  defp to_int(%{"ctor" => "Ok", "args" => [inner]}, default), do: to_int(inner, default)
  defp to_int({:Ok, inner}, default), do: to_int(inner, default)
  defp to_int(other, _default) when is_number(other), do: trunc(other)
  defp to_int(_other, default), do: default
end
