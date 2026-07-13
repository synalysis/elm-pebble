defmodule Elmx.Runtime.Core.Collections.Dict do
  @moduledoc false

  alias Elmx.Runtime.Core
  alias Elmx.Runtime.Core.Collections.Pairs
  alias Elmx.Types

  @type dict :: Types.elm_dict()

  defp wrap(map) when is_map(map), do: {:elmx_dict, map}

  defp unwrap({:elmx_dict, map}) when is_map(map), do: map

  defp unwrap({:elmx_dict, pairs}) when is_list(pairs) do
    Enum.reduce(pairs, %{}, fn {k, v}, acc -> Map.put(acc, k, v) end)
  end

  defp unwrap(items) when is_list(items) do
    Enum.reduce(items, %{}, fn {k, v}, acc -> Map.put(acc, k, v) end)
  end

  defp sorted_pairs(dict) do
    dict
    |> unwrap()
    |> Map.to_list()
    |> Enum.sort(fn {ka, _}, {kb, _} ->
      case Core.basics_compare(ka, kb) do
        :LT -> true
        _ -> false
      end
    end)
  end

  @spec dict_empty() :: dict()
  def dict_empty, do: wrap(%{})

  @spec dict_from_list([Types.dict_entry_input()]) :: dict()
  def dict_from_list(pairs) when is_list(pairs) do
    pairs
    |> Enum.reduce(%{}, fn pair, acc ->
      {key, value} = Pairs.normalize_pair(pair)
      Map.put(acc, key, value)
    end)
    |> wrap()
  end

  @spec dict_insert(Types.elm_value(), Types.elm_value(), dict()) :: dict()
  def dict_insert(key, value, dict), do: wrap(Map.put(unwrap(dict), key, value))

  @spec dict_get(Types.elm_value(), dict()) :: Types.maybe_native()
  def dict_get(key, dict) do
    case Map.fetch(unwrap(dict), key) do
      {:ok, value} -> {:Just, value}
      :error -> :Nothing
    end
  end

  @spec dict_get_with_default_int(integer(), Types.elm_value(), dict()) :: integer()
  def dict_get_with_default_int(default, key, dict) when is_integer(default) do
    case dict_get(key, dict) do
      {:Just, value} -> Pairs.to_int(value, default)
      _ -> default
    end
  end

  @spec dict_member(Types.elm_value(), dict()) :: boolean()
  def dict_member(key, dict), do: Map.has_key?(unwrap(dict), key)

  @spec dict_size(dict()) :: integer()
  def dict_size(dict), do: map_size(unwrap(dict))

  @spec dict_remove(Types.elm_value(), dict()) :: dict()
  def dict_remove(key, dict), do: wrap(Map.delete(unwrap(dict), key))

  @spec dict_is_empty(dict()) :: boolean()
  def dict_is_empty(dict), do: unwrap(dict) == %{}

  @spec dict_singleton(Types.elm_value(), Types.elm_value()) :: dict()
  def dict_singleton(key, value), do: wrap(%{key => value})

  @spec dict_keys(dict()) :: list()
  def dict_keys(dict) do
    dict
    |> sorted_pairs()
    |> Enum.map(fn {k, _} -> k end)
  end

  @spec dict_values(dict()) :: list()
  def dict_values(dict) do
    dict
    |> sorted_pairs()
    |> Enum.map(fn {_, v} -> v end)
  end

  @spec dict_to_list(dict()) :: list()
  def dict_to_list(dict), do: sorted_pairs(dict)

  @spec dict_map(Types.elm_hof(), dict()) :: dict()
  def dict_map(fun, dict) do
    dict
    |> sorted_pairs()
    |> Enum.map(fn {k, v} -> {k, Core.apply2(fun, k, v)} end)
    |> Map.new()
    |> wrap()
  end

  @spec dict_foldl(Types.elm_hof(), Types.fold_acc(), dict()) :: Types.fold_acc()
  def dict_foldl(fun, acc, dict) do
    Enum.reduce(sorted_pairs(dict), acc, fn {k, v}, acc0 -> Core.apply3(fun, k, v, acc0) end)
  end

  @spec dict_foldr(Types.elm_hof(), Types.fold_acc(), dict()) :: Types.fold_acc()
  def dict_foldr(fun, acc, dict) do
    dict
    |> sorted_pairs()
    |> Enum.reverse()
    |> Enum.reduce(acc, fn {k, v}, acc0 -> Core.apply3(fun, k, v, acc0) end)
  end

  @spec dict_filter(Types.elm_hof(), dict()) :: dict()
  def dict_filter(fun, dict) do
    dict
    |> sorted_pairs()
    |> Enum.filter(fn {k, v} -> Core.apply2(fun, k, v) end)
    |> Map.new()
    |> wrap()
  end

  @spec dict_partition(Types.elm_hof(), dict()) :: {dict(), dict()}
  def dict_partition(fun, dict) do
    {yes, no} = Enum.split_with(sorted_pairs(dict), fn {k, v} -> Core.apply2(fun, k, v) end)
    {wrap(Map.new(yes)), wrap(Map.new(no))}
  end

  @spec dict_union(dict(), dict()) :: dict()
  def dict_union(left, right) do
    wrap(Map.merge(unwrap(left), unwrap(right)))
  end

  @spec dict_intersect(dict(), dict()) :: dict()
  def dict_intersect(left, right) do
    right_map = unwrap(right)

    left
    |> unwrap()
    |> Enum.filter(fn {k, _} -> Map.has_key?(right_map, k) end)
    |> Enum.map(fn {k, _} -> {k, Map.fetch!(right_map, k)} end)
    |> Map.new()
    |> wrap()
  end

  @spec dict_diff(dict(), dict()) :: dict()
  def dict_diff(left, right) do
    right_keys = MapSet.new(Map.keys(unwrap(right)))

    left
    |> unwrap()
    |> Enum.reject(fn {k, _} -> MapSet.member?(right_keys, k) end)
    |> Map.new()
    |> wrap()
  end

  @spec dict_merge(
          Types.elm_hof(),
          Types.elm_hof(),
          Types.elm_hof(),
          dict(),
          dict(),
          Types.fold_acc()
        ) :: Types.fold_acc()
  def dict_merge(left_step, both_step, right_step, left, right, result) do
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

  @spec dict_merge(Types.elm_hof(), Types.elm_hof(), Types.elm_hof(), dict(), dict()) :: dict()
  def dict_merge(left_step, both_step, right_step, left, right) do
    dict_merge(left_step, both_step, right_step, left, right, wrap(%{}))
  end

  @spec dict_update(Types.elm_value(), Types.elm_hof(), dict()) :: dict()
  def dict_update(key, alter, dict) do
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

  def dict_fetch!(key, dict) do
    case Map.fetch(unwrap(dict), key) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "dict_fetch! missing key #{inspect(key)}"
    end
  end
end
