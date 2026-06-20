defmodule Elmx.Runtime.Core.List do
  @moduledoc """
  Elm `List` runtime helpers for generated Elixir code.
  """

  alias Elmx.Runtime.Core
  alias Elmx.Types

  @type elm_list :: Types.elm_list()

  @doc """
  Elm `List.head` — returns `Just` / `Nothing` in the shape generated `case` expects.
  """
  @spec list_head(elm_list()) :: Types.maybe_like()
  def list_head([head | _]), do: {:Just, head}
  def list_head([]), do: :Nothing
  def list_head(_), do: :Nothing

  @spec list_tail(elm_list()) :: elm_list()
  def list_tail([_ | tail]), do: tail
  def list_tail(_), do: []

  @spec list_length(elm_list()) :: integer()
  def list_length(list) when is_list(list), do: length(list)
  def list_length(_), do: 0

  @spec list_is_empty(elm_list()) :: boolean()
  def list_is_empty(list) when is_list(list), do: list == []

  @spec list_reverse(elm_list()) :: elm_list()
  def list_reverse(list) when is_list(list), do: Enum.reverse(list)

  @spec list_append(elm_list(), elm_list()) :: elm_list()
  def list_append(left, right) when is_list(left) and is_list(right), do: left ++ right

  @spec list_concat(elm_list()) :: elm_list()
  def list_concat(lists) when is_list(lists), do: Enum.concat(lists)

  @spec list_cons(Types.elm_value(), elm_list()) :: elm_list()
  def list_cons(head, tail) when is_list(tail), do: [head | tail]

  @spec list_singleton(Types.elm_value()) :: elm_list()
  def list_singleton(value), do: [value]

  @spec list_range(integer(), integer()) :: elm_list()
  def list_range(lo, hi) when is_integer(lo) and is_integer(hi) do
    if lo > hi do
      []
    else
      Enum.to_list(lo..hi)
    end
  end

  @spec list_take(integer(), elm_list()) :: elm_list()
  def list_take(n, list) when is_integer(n) and is_list(list), do: Enum.take(list, max(n, 0))

  @spec list_drop(integer(), elm_list()) :: elm_list()
  def list_drop(n, list) when is_integer(n) and is_list(list), do: Enum.drop(list, max(n, 0))

  @spec list_partition(Types.elm_hof(), elm_list()) :: {elm_list(), elm_list()}
  def list_partition(fun, list) when is_list(list),
    do: Enum.split_with(list, &Core.apply1(fun, &1))

  @spec list_unzip(elm_list()) :: {elm_list(), elm_list()}
  def list_unzip(list) when is_list(list) do
    Enum.map(list, fn
      {a, b} -> {a, b}
      [a, b] -> {a, b}
      %{"ctor" => "Tuple", "args" => [a, b]} -> {a, b}
      %{ctor: :Tuple, args: [a, b]} -> {a, b}
      other -> {other, other}
    end)
    |> Enum.unzip()
  end

  @spec list_intersperse(Types.elm_value(), elm_list()) :: elm_list()
  def list_intersperse(sep, list) when is_list(list) do
    case list do
      [] -> []
      [first | rest] -> [first | Enum.flat_map(rest, fn item -> [sep, item] end)]
    end
  end

  @spec list_map2(Types.elm_hof(), elm_list(), elm_list()) :: elm_list()
  def list_map2(fun, as, bs) when is_list(as) and is_list(bs) do
    Enum.map(Enum.zip(as, bs), fn {a, b} -> Core.apply2(fun, a, b) end)
  end

  @spec list_map3(Types.elm_hof(), elm_list(), elm_list(), elm_list()) :: elm_list()
  def list_map3(fun, as, bs, cs) when is_list(as) and is_list(bs) and is_list(cs) do
    Enum.map(Enum.zip(as, Enum.zip(bs, cs)), fn {a, {b, c}} -> Core.apply3(fun, a, b, c) end)
  end

  @spec list_map4(Types.elm_hof(), elm_list(), elm_list(), elm_list(), elm_list()) :: elm_list()
  def list_map4(fun, as, bs, cs, ds) when is_list(as) and is_list(bs) and is_list(cs) and is_list(ds) do
    Enum.map(Enum.zip(as, Enum.zip(bs, Enum.zip(cs, ds))), fn {a, {b, {c, d}}} ->
      Core.apply4(fun, a, b, c, d)
    end)
  end

  @spec list_map5(Types.elm_hof(), elm_list(), elm_list(), elm_list(), elm_list(), elm_list()) ::
          elm_list()
  def list_map5(fun, as, bs, cs, ds, es)
      when is_list(as) and is_list(bs) and is_list(cs) and is_list(ds) and is_list(es) do
    Enum.map(Enum.zip(as, Enum.zip(bs, Enum.zip(cs, Enum.zip(ds, es)))), fn {a, {b, {c, {d, e}}}} ->
      Core.apply5(fun, a, b, c, d, e)
    end)
  end

  @doc "Elm `List.map` with unary or partially applied callbacks."
  @spec map(Types.elm_hof(), elm_list()) :: elm_list()
  def map(fun, list) when is_list(list) do
    Enum.map(list, fn item -> Core.apply1(fun, item) end)
  end

  @doc "Elm `List.filter`."
  @spec filter(Types.elm_hof(), elm_list()) :: elm_list()
  def filter(fun, list) when is_list(list) do
    Enum.filter(list, fn item -> Core.apply1(fun, item) end)
  end

  @doc "Elm `List.any`."
  @spec any(Types.elm_hof(), elm_list()) :: boolean()
  def any(fun, list) when is_list(list) do
    Enum.any?(list, fn item -> Core.apply1(fun, item) end)
  end

  @doc "Elm `List.filterMap`."
  @spec filter_map(Types.elm_hof(), elm_list()) :: elm_list()
  def filter_map(fun, list) when is_list(list) do
    Enum.flat_map(list, fn item ->
      case Core.apply1(fun, item) do
        :Nothing -> []
        {:Just, value} -> [value]
        %{"ctor" => "Nothing"} -> []
        %{"ctor" => "Just", "args" => [value]} -> [value]
        _ -> []
      end
    end)
  end

  @doc "Elm `List.concatMap`."
  @spec concat_map(Types.elm_hof(), elm_list()) :: elm_list()
  def concat_map(fun, list) when is_list(list) do
    Enum.flat_map(list, fn item ->
      case Core.apply1(fun, item) do
        sublist when is_list(sublist) -> sublist
        _ -> []
      end
    end)
  end

  @doc "Elm `List.sortBy`."
  @spec sort_by(Types.elm_hof(), elm_list()) :: elm_list()
  def sort_by(fun, list) when is_list(list) do
    Enum.sort_by(list, fn item -> Core.apply1(fun, item) end)
  end

  @doc """
  Elm `List.foldl` — left fold with curried or 2-arity callbacks.
  """
  @spec foldl(Types.elm_hof(), Types.fold_acc(), elm_list()) :: Types.fold_acc()
  def foldl(fun, acc, list) when is_list(list) do
    Enum.reduce(list, acc, fn item, acc0 -> Core.apply2(fun, item, acc0) end)
  end

  @doc """
  Elm `List.foldr` — right fold with curried or 2-arity callbacks.
  """
  @spec foldr(Types.elm_hof(), Types.fold_acc(), elm_list()) :: Types.fold_acc()
  def foldr(fun, acc, list) when is_list(list) do
    Enum.reduce(Enum.reverse(list), acc, fn item, acc0 -> Core.apply2(fun, item, acc0) end)
  end

  @doc "Elm `List.repeat`."
  @spec list_repeat(integer(), Types.elm_value()) :: elm_list()
  def list_repeat(n, value) when is_integer(n) and n >= 0, do: List.duplicate(value, n)

  @doc "Elm `List.member`."
  @spec member(Types.elm_value(), elm_list()) :: boolean()
  def member(value, list) when is_list(list), do: value in list

  @doc "Elm `List.all`."
  @spec all(Types.elm_hof(), elm_list()) :: boolean()
  def all(fun, list) when is_list(list) do
    Enum.all?(list, fn item -> Core.apply1(fun, item) end)
  end

  @doc "Elm `List.sort`."
  @spec sort(elm_list()) :: elm_list()
  def sort(list) when is_list(list), do: Enum.sort(list)

  @doc "Elm `List.product`."
  @spec list_product(elm_list()) :: number()
  def list_product(list) when is_list(list) do
    Enum.reduce(list, 1, fn item, acc ->
      case to_number(item) do
        {:ok, n} -> acc * n
        :error -> acc
      end
    end)
  end

  @doc "Elm `List.maximum`."
  @spec list_maximum(elm_list()) :: Types.maybe_like()
  def list_maximum([]), do: :Nothing
  def list_maximum([first | rest]) do
    Enum.reduce(rest, first, fn item, acc ->
      if Core.basics_compare(item, acc) == :GT, do: item, else: acc
    end)
    |> just_wrap()
  end

  @doc "Elm `List.minimum`."
  @spec list_minimum(elm_list()) :: Types.maybe_like()
  def list_minimum([]), do: :Nothing
  def list_minimum([first | rest]) do
    Enum.reduce(rest, first, fn item, acc ->
      if Core.basics_compare(item, acc) == :LT, do: item, else: acc
    end)
    |> just_wrap()
  end

  @doc "Elm `List.sum`."
  @spec list_sum(elm_list()) :: number()
  def list_sum(list) when is_list(list) do
    Enum.reduce(list, 0, fn item, acc ->
      case to_number(item) do
        {:ok, n} -> acc + n
        :error -> acc
      end
    end)
  end

  @doc "Elm `List.sortWith` — comparison returns `Order` (LT/EQ/GT)."
  @spec sort_with(Types.elm_hof(), elm_list()) :: elm_list()
  def sort_with(fun, list) when is_list(list) do
    Enum.sort(list, fn a, b ->
      case Core.apply2(fun, a, b) do
        order -> compare_order_value(order) != :gt
      end
    end)
  rescue
    _ -> Enum.sort(list)
  end

  @doc """
  Elm `List.indexedMap` — supports 2-arity functions and curried `\\i -> \\v ->` lambdas.
  """
  @spec indexed_map(Types.elm_hof(), elm_list()) :: elm_list()
  def indexed_map(fun, list) when is_function(fun, 2) and is_list(list) do
    Enum.map(Enum.with_index(list), fn {item, index} -> fun.(index, item) end)
  end

  def indexed_map(fun, list) when is_function(fun, 1) and is_list(list) do
    Enum.map(Enum.with_index(list), fn {item, index} -> Core.apply2(fun, index, item) end)
  end

  defp compare_order_value(%{"ctor" => ctor}) when is_binary(ctor),
    do: compare_order_value(%{ctor: String.to_atom(ctor)})

  defp compare_order_value(%{ctor: ctor}) when is_atom(ctor) do
    case ctor |> Atom.to_string() |> String.upcase() do
      "LT" -> :lt
      "EQ" -> :eq
      "GT" -> :gt
      _ -> :eq
    end
  end

  defp compare_order_value(:LT), do: :lt
  defp compare_order_value(:EQ), do: :eq
  defp compare_order_value(:GT), do: :gt
  defp compare_order_value(_), do: :eq

  defp just_wrap(value), do: {:Just, value}

  defp to_number(n) when is_integer(n), do: {:ok, n}
  defp to_number(n) when is_float(n), do: {:ok, n}
  defp to_number(%{"ctor" => "Float", "args" => [f]}), do: {:ok, f * 1.0}
  defp to_number(%{ctor: :Float, args: [f]}), do: {:ok, f * 1.0}
  defp to_number(_), do: :error
end
