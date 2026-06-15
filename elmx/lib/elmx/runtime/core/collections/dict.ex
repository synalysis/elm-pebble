defmodule Elmx.Runtime.Core.Collections.Dict do
  @moduledoc false

  alias Elmx.Runtime.Core
  alias Elmx.Runtime.Core.Collections.Pairs
  alias Elmx.Types

  @type dict :: Types.elm_dict()

  @spec dict_from_list([Types.dict_entry_input()]) :: dict()
  def dict_from_list(pairs) when is_list(pairs) do
    Enum.reduce(pairs, [], fn pair, acc ->
      {key, value} = Pairs.normalize_pair(pair)
      dict_insert(key, value, acc)
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
      {:Just, value} -> Pairs.to_int(value, default)
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

  def dict_fetch!(key, dict) when is_integer(key) do
    case Enum.find(dict, fn {k, _} -> k == key end) do
      {_, value} -> value
      nil -> raise ArgumentError, "dict_fetch! missing key #{inspect(key)}"
    end
  end

end
