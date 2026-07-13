defmodule Elmx.Runtime.Core.Collections.Array do
  @moduledoc false

  alias Elmx.Runtime.Core
  alias Elmx.Runtime.Core.Collections.Pairs
  alias Elmx.Types

  @type array :: Types.elm_array()

  def array_empty, do: []

  @spec array_from_list(list()) :: list()
  def array_from_list(items) when is_list(items), do: items

  @spec array_length(list()) :: integer()
  def array_length(array) when is_list(array), do: length(array)

  @spec array_get(integer(), list()) :: Types.maybe_native()
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
      {:Just, value} -> Pairs.to_int(value, default)
      _ -> default
    end
  end

  @spec array_set(integer(), Types.elm_value(), list()) :: list()
  def array_set(index, value, array) when is_integer(index) and is_list(array) do
    if index < 0 or index >= length(array) do
      array
    else
      List.replace_at(array, index, value)
    end
  end

  @spec array_push(Types.elm_value(), list()) :: list()
  def array_push(value, array) when is_list(array), do: array ++ [value]

  @spec array_repeat(integer(), Types.elm_value()) :: list()
  def array_repeat(n, value) when is_integer(n), do: List.duplicate(value, max(n, 0))

  @spec array_initialize(integer(), Types.elm_hof()) :: list()
  def array_initialize(n, _fun) when is_integer(n) and n <= 0, do: []

  def array_initialize(n, fun) when is_integer(n) and is_function(fun, 1) do
    for i <- 0..(n - 1)//1, do: Core.apply1(fun, i)
  end

  def array_initialize(n, value) when is_integer(n), do: List.duplicate(value, max(n, 0))

  @spec array_is_empty(list()) :: boolean()
  def array_is_empty(array), do: array == []

  @spec array_to_list(list()) :: list()
  def array_to_list(array), do: array

  @spec array_to_indexed_list(list()) :: list()
  def array_to_indexed_list(array), do: Enum.with_index(array)

  @spec array_map(Types.elm_hof(), list()) :: list()
  def array_map(fun, array), do: Core.map(fun, array)

  @spec array_indexed_map(Types.elm_hof(), list()) :: list()
  def array_indexed_map(fun, array), do: Core.indexed_map(fun, array)

  @spec array_foldl(Types.elm_hof(), Types.fold_acc(), list()) :: Types.fold_acc()
  def array_foldl(fun, acc, array), do: Core.foldl(fun, acc, array)

  @spec array_foldr(Types.elm_hof(), Types.fold_acc(), list()) :: Types.fold_acc()
  def array_foldr(fun, acc, array), do: Core.foldr(fun, acc, array)

  @spec array_filter(Types.elm_hof(), list()) :: list()
  def array_filter(fun, array), do: Core.filter(fun, array)

  @spec array_append(list(), list()) :: list()
  def array_append(left, right), do: left ++ right

  @spec array_slice(integer(), integer(), list()) :: list()
  def array_slice(start, length, array) when is_integer(start) and is_integer(length) do
    array |> Enum.drop(start) |> Enum.take(length)
  end


end
