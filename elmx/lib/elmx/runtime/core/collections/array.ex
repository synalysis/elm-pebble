defmodule Elmx.Runtime.Core.Collections.Array do
  @moduledoc false
  alias Elmx.Types, as: Types


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

  @spec array_push(Types.elm_value(), list() | tuple() | map()) :: list()
  def array_push(value, array) when is_list(array), do: array ++ [value]

  # elm/core Array tree leaves/nodes may reach push when list-backed helpers mix with
  # generated Array.* — flatten via to_list semantics then append.
  def array_push(value, array), do: array_to_list(array) ++ [value]

  @spec array_repeat(integer(), Types.elm_value()) :: list()
  def array_repeat(n, value) when is_integer(n), do: List.duplicate(value, max(n, 0))

  @spec array_initialize(integer(), Types.elm_hof()) :: list()
  def array_initialize(n, _fun) when is_integer(n) and n <= 0, do: []

  def array_initialize(n, fun) when is_integer(n) and is_function(fun, 1) do
    for i <- 0..(n - 1)//1, do: Core.apply1(fun, i)
  end

  def array_initialize(n, value) when is_integer(n), do: List.duplicate(value, max(n, 0))

  @spec array_is_empty(list()) :: boolean()
  def array_is_empty(array), do: array_to_list(array) == []

  @spec array_to_list(term()) :: list()
  def array_to_list(array) when is_list(array), do: array

  def array_to_list({:Array_elm_builtin, _len, _shift, tree, tail}),
    do: flatten_js_tree(tree) ++ flatten_js_tree(tail)

  def array_to_list({:ctor, "Array_elm_builtin", [_len, _shift, tree, tail]}),
    do: flatten_js_tree(tree) ++ flatten_js_tree(tail)

  def array_to_list(%{ctor: :Array_elm_builtin, args: [_len, _shift, tree, tail]}),
    do: flatten_js_tree(tree) ++ flatten_js_tree(tail)

  def array_to_list(%{"ctor" => "Array_elm_builtin", "args" => [_len, _shift, tree, tail]}),
    do: flatten_js_tree(tree) ++ flatten_js_tree(tail)

  def array_to_list(array), do: flatten_array_tree(array)

  @spec array_to_indexed_list(term()) :: list()
  def array_to_indexed_list(array), do: Enum.with_index(array_to_list(array))

  @spec array_map(Types.elm_hof(), list()) :: list()
  def array_map(fun, array), do: Core.map(fun, array_to_list(array))

  @spec array_indexed_map(Types.elm_hof(), list()) :: list()
  def array_indexed_map(fun, array), do: Core.indexed_map(fun, array_to_list(array))

  @spec array_foldl(Types.elm_hof(), Types.fold_acc(), list()) :: Types.fold_acc()
  def array_foldl(fun, acc, array), do: Core.foldl(fun, acc, array_to_list(array))

  @spec array_foldr(Types.elm_hof(), Types.fold_acc(), list()) :: Types.fold_acc()
  def array_foldr(fun, acc, array), do: Core.foldr(fun, acc, array_to_list(array))

  @spec array_filter(Types.elm_hof(), list()) :: list()
  def array_filter(fun, array), do: Core.filter(fun, array_to_list(array))

  @spec array_append(list(), list()) :: list()
  def array_append(left, right), do: array_to_list(left) ++ array_to_list(right)

  @spec array_slice(integer(), integer(), list()) :: list()
  def array_slice(start, length, array) when is_integer(start) and is_integer(length) do
    array |> array_to_list() |> Enum.drop(start) |> Enum.take(length)
  end

  # --- Elm.JsArray kernel (arrays are plain lists in elmx) ---

  @spec js_array_singleton(Types.elm_value()) :: list()
  def js_array_singleton(value), do: [value]

  @spec js_array_initialize(integer(), integer(), Types.elm_hof()) :: list()
  def js_array_initialize(size, _offset, _fun) when is_integer(size) and size <= 0, do: []

  def js_array_initialize(size, offset, fun)
      when is_integer(size) and is_integer(offset) and is_function(fun, 1) do
    for i <- 0..(size - 1)//1, do: Core.apply1(fun, offset + i)
  end

  def js_array_initialize(size, offset, fun) when is_integer(size) and is_integer(offset) do
    for i <- 0..(max(size, 0) - 1)//1, do: Core.apply1(fun, offset + i)
  end

  @spec js_array_initialize_from_list(integer(), list()) :: {list(), list()}
  def js_array_initialize_from_list(max, list) when is_integer(max) and is_list(list) do
    n = max(max, 0)
    {Enum.take(list, n), Enum.drop(list, n)}
  end

  @spec js_array_unsafe_get(integer(), list()) :: Types.elm_value()
  def js_array_unsafe_get(index, array) when is_integer(index) and is_list(array) do
    Enum.at(array, index)
  end

  @spec js_array_unsafe_set(integer(), Types.elm_value(), list()) :: list()
  def js_array_unsafe_set(index, value, array)
      when is_integer(index) and is_list(array) do
    List.replace_at(array, index, value)
  end

  @spec js_array_indexed_map(Types.elm_hof(), integer(), list()) :: list()
  def js_array_indexed_map(fun, offset, array)
      when is_integer(offset) and is_list(array) do
    array
    |> Enum.with_index()
    |> Enum.map(fn {value, i} -> Core.apply2(fun, offset + i, value) end)
  end

  @spec js_array_slice(integer(), integer(), list()) :: list()
  def js_array_slice(from, to, array) when is_integer(from) and is_integer(to) and is_list(array) do
    len = length(array)
    start = normalize_js_index(from, len)
    stop = normalize_js_index(to, len)

    if stop <= start do
      []
    else
      Enum.slice(array, start, stop - start)
    end
  end

  @spec js_array_append_n(integer(), list(), list()) :: list()
  def js_array_append_n(n, dest, source)
      when is_integer(n) and is_list(dest) and is_list(source) do
    dest_len = length(dest)
    items_to_copy = min(max(n - dest_len, 0), length(source))
    dest ++ Enum.take(source, items_to_copy)
  end

  defp normalize_js_index(index, len) when index < 0, do: max(len + index, 0)
  defp normalize_js_index(index, len), do: min(index, len)

  defp flatten_js_tree(node) when is_list(node), do: Enum.flat_map(node, &flatten_js_tree/1)
  defp flatten_js_tree({:ctor, _name, args}) when is_list(args), do: Enum.flat_map(args, &flatten_js_tree/1)
  defp flatten_js_tree(%{ctor: _, args: args}) when is_list(args), do: Enum.flat_map(args, &flatten_js_tree/1)
  defp flatten_js_tree(%{"ctor" => _, "args" => args}) when is_list(args), do: Enum.flat_map(args, &flatten_js_tree/1)
  defp flatten_js_tree(tuple) when is_tuple(tuple) and tuple_size(tuple) > 0 do
    case elem(tuple, 0) do
      :Array_elm_builtin -> array_to_list(tuple)
      :SubTree -> tuple |> Tuple.to_list() |> tl() |> Enum.flat_map(&flatten_js_tree/1)
      :Leaf -> tuple |> Tuple.to_list() |> tl() |> Enum.flat_map(&flatten_js_tree/1)
      _ when is_atom(elem(tuple, 0)) ->
        tuple |> Tuple.to_list() |> tl() |> Enum.flat_map(&flatten_js_tree/1)
      _ ->
        tuple |> Tuple.to_list() |> Enum.flat_map(&flatten_js_tree/1)
    end
  end
  defp flatten_js_tree(value), do: [value]

  defp flatten_array_tree(array) when is_list(array), do: array
  defp flatten_array_tree({:ctor, _name, args}) when is_list(args), do: Enum.flat_map(args, &flatten_array_tree/1)
  defp flatten_array_tree(%{ctor: _, args: args}) when is_list(args), do: Enum.flat_map(args, &flatten_array_tree/1)
  defp flatten_array_tree(%{"ctor" => _, "args" => args}) when is_list(args), do: Enum.flat_map(args, &flatten_array_tree/1)
  defp flatten_array_tree(tuple) when is_tuple(tuple), do: flatten_js_tree(tuple)
  defp flatten_array_tree(value), do: [value]
end
