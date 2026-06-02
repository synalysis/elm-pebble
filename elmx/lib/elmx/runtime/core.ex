defmodule Elmx.Runtime.Core do
  @moduledoc """
  Elm `elm/core` runtime helpers for generated Elixir code.
  """

  @spec maybe_with_default(term(), term()) :: term()
  def maybe_with_default(default, maybe) do
    case maybe do
      :Nothing -> default
      {:Just, value} -> value
      %{"ctor" => "Nothing"} -> default
      %{"ctor" => "Just", "args" => [value]} -> value
      %{ctor: :Nothing} -> default
      %{ctor: :Just, args: [value]} -> value
      %{"ctor" => "Err"} -> default
      {:Err, _} -> default
      nil -> default
      other -> other
    end
  end

  @spec maybe_map(term(), function()) :: term()
  def maybe_map(_f, :Nothing), do: :Nothing
  def maybe_map(_f, %{"ctor" => "Nothing"}), do: :Nothing
  def maybe_map(_f, %{ctor: :Nothing}), do: :Nothing

  def maybe_map(f, {:Just, value}) when is_function(f, 1), do: {:Just, f.(value)}
  def maybe_map(f, %{"ctor" => "Just", "args" => [value]}) when is_function(f, 1), do: {:Just, f.(value)}
  def maybe_map(f, %{ctor: :Just, args: [value]}) when is_function(f, 1), do: {:Just, f.(value)}
  def maybe_map(_f, other), do: other

  @spec maybe_and_then(function(), term()) :: term()
  def maybe_and_then(_f, :Nothing), do: :Nothing
  def maybe_and_then(_f, %{"ctor" => "Nothing"}), do: :Nothing
  def maybe_and_then(_f, %{ctor: :Nothing}), do: :Nothing

  def maybe_and_then(f, {:Just, value}) when is_function(f, 1), do: f.(value)
  def maybe_and_then(f, %{"ctor" => "Just", "args" => [value]}) when is_function(f, 1), do: f.(value)
  def maybe_and_then(f, %{ctor: :Just, args: [value]}) when is_function(f, 1), do: f.(value)
  def maybe_and_then(_f, other), do: other

  @spec maybe_map2(term(), term(), function()) :: term()
  def maybe_map2(:Nothing, _, _), do: :Nothing
  def maybe_map2(_, :Nothing, _), do: :Nothing
  def maybe_map2(%{"ctor" => "Nothing"}, _, _), do: :Nothing
  def maybe_map2(_, %{"ctor" => "Nothing"}, _), do: :Nothing

  def maybe_map2({:Just, a}, {:Just, b}, f) when is_function(f, 2), do: {:Just, f.(a, b)}

  def maybe_map2(%{"ctor" => "Just", "args" => [a]}, %{"ctor" => "Just", "args" => [b]}, f)
      when is_function(f, 2),
      do: {:Just, f.(a, b)}

  def maybe_map2(other_a, other_b, f), do: maybe_map2(normalize_maybe(other_a), normalize_maybe(other_b), f)

  @spec result_map(function(), term()) :: term()
  def result_map(_f, {:Err, _} = err), do: err
  def result_map(_f, %{"ctor" => "Err"} = err), do: err
  def result_map(f, {:Ok, value}) when is_function(f, 1), do: {:Ok, f.(value)}
  def result_map(f, %{"ctor" => "Ok", "args" => [value]}) when is_function(f, 1), do: {:Ok, f.(value)}
  def result_map(_f, other), do: other

  @spec result_and_then(function(), term()) :: term()
  def result_and_then(_f, {:Err, _} = err), do: err
  def result_and_then(_f, %{"ctor" => "Err"} = err), do: err
  def result_and_then(f, {:Ok, value}) when is_function(f, 1), do: f.(value)
  def result_and_then(f, %{"ctor" => "Ok", "args" => [value]}) when is_function(f, 1), do: f.(value)
  def result_and_then(_f, other), do: other

  @spec result_map_error(term(), term()) :: term()
  def result_map_error(f, {:Err, err}) when is_function(f, 1), do: {:Err, f.(err)}
  def result_map_error(f, %{"ctor" => "Err", "args" => [err]}) when is_function(f, 1), do: {:Err, f.(err)}
  def result_map_error(_f, {:Ok, _} = ok), do: ok
  def result_map_error(_f, %{"ctor" => "Ok"} = ok), do: ok
  def result_map_error(_f, other), do: other

  @spec result_with_default(term(), term()) :: term()
  def result_with_default(default, result) do
    case result do
      {:Ok, value} -> value
      %{"ctor" => "Ok", "args" => [value]} -> value
      _ -> default
    end
  end

  @spec random_generator(integer(), integer()) :: map()
  def random_generator(low, high) when is_integer(low) and is_integer(high) do
    %{low: low, high: high}
  end

  @spec random_int(map()) :: integer()
  def random_int(%{low: low, high: high}) when is_integer(low) and is_integer(high) do
    case corpus_fixed_random_int() do
      n when is_integer(n) -> clamp_int(n, low, high)
      _ -> low + rem(:rand.uniform(max(high - low + 1, 1)), max(high - low + 1, 1))
    end
  end

  def random_int(%{"low" => low, "high" => high}), do: random_int(%{low: low, high: high})

  defp corpus_fixed_random_int do
    Process.get(:elmx_corpus_fixed_random_int) ||
      Application.get_env(:elmx, :corpus_fixed_random_int)
  end

  defp clamp_int(n, low, high) when is_integer(n) and is_integer(low) and is_integer(high) do
    min(max(n, low), high)
  end

  @doc """
  Elm `List.head` — returns `Just` / `Nothing` in the shape generated `case` expects.
  """
  @spec list_head(list()) :: {:Just, term()} | :Nothing
  def list_head([head | _]), do: {:Just, head}
  def list_head([]), do: :Nothing
  def list_head(_), do: :Nothing

  @spec list_tail(list()) :: list()
  def list_tail([_ | tail]), do: tail
  def list_tail(_), do: []

  @spec list_length(list()) :: integer()
  def list_length(list) when is_list(list), do: length(list)
  def list_length(_), do: 0

  @spec list_is_empty(list()) :: boolean()
  def list_is_empty(list) when is_list(list), do: list == []

  @spec list_reverse(list()) :: list()
  def list_reverse(list) when is_list(list), do: Enum.reverse(list)

  @spec list_append(list(), list()) :: list()
  def list_append(left, right) when is_list(left) and is_list(right), do: left ++ right

  @spec list_concat(list()) :: list()
  def list_concat(lists) when is_list(lists), do: Enum.concat(lists)

  @spec list_cons(term(), list()) :: list()
  def list_cons(head, tail) when is_list(tail), do: [head | tail]

  @spec list_singleton(term()) :: list()
  def list_singleton(value), do: [value]

  @spec list_range(integer(), integer()) :: list()
  def list_range(lo, hi) when is_integer(lo) and is_integer(hi), do: Enum.to_list(lo..hi)

  @spec list_take(integer(), list()) :: list()
  def list_take(n, list) when is_integer(n) and is_list(list), do: Enum.take(list, max(n, 0))

  @spec list_drop(integer(), list()) :: list()
  def list_drop(n, list) when is_integer(n) and is_list(list), do: Enum.drop(list, max(n, 0))

  @spec list_partition(term(), list()) :: {list(), list()}
  def list_partition(fun, list) when is_list(list),
    do: Enum.split_with(list, &apply1(fun, &1))

  @spec list_unzip(list()) :: {list(), list()}
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

  @spec list_intersperse(term(), list()) :: list()
  def list_intersperse(sep, list) when is_list(list) do
    case list do
      [] -> []
      [first | rest] -> [first | Enum.flat_map(rest, fn item -> [sep, item] end)]
    end
  end

  @spec list_map2(term(), list(), list()) :: list()
  def list_map2(fun, as, bs) when is_list(as) and is_list(bs) do
    Enum.map(Enum.zip(as, bs), fn {a, b} -> apply2(fun, a, b) end)
  end

  @spec list_map3(term(), list(), list(), list()) :: list()
  def list_map3(fun, as, bs, cs) when is_list(as) and is_list(bs) and is_list(cs) do
    Enum.map(Enum.zip([as, bs, cs]), fn [a, b, c] -> apply3(fun, a, b, c) end)
  end

  @spec basics_not(boolean()) :: boolean()
  def basics_not(value) when is_boolean(value), do: not value
  def basics_not(value), do: !value

  @spec basics_negate(number()) :: number()
  def basics_negate(n) when is_number(n), do: -n
  def basics_negate(_), do: 0

  @spec basics_abs(number()) :: number()
  def basics_abs(n) when is_number(n), do: abs(n)
  def basics_abs(_), do: 0

  @spec basics_max(term(), term()) :: term()
  def basics_max(a, b), do: max(a, b)

  @spec basics_min(term(), term()) :: term()
  def basics_min(a, b), do: min(a, b)

  @spec basics_mod_by(integer(), integer()) :: integer()
  def basics_mod_by(base, value) when is_integer(base) and base != 0, do: Integer.mod(value, base)
  def basics_mod_by(_base, _value), do: 0

  @spec basics_clamp(term(), term(), term()) :: term()
  def basics_clamp(low, high, value), do: max(low, min(high, value))

  @spec result_to_maybe(term()) :: term()
  def result_to_maybe({:Ok, value}), do: {:Just, value}
  def result_to_maybe(%{"ctor" => "Ok", "args" => [value]}), do: {:Just, value}
  def result_to_maybe(_), do: :Nothing

  @spec result_from_maybe(term(), term()) :: term()
  def result_from_maybe(err, maybe) do
    case maybe do
      {:Just, value} -> {:Ok, value}
      %{"ctor" => "Just", "args" => [value]} -> {:Ok, value}
      _ -> {:Err, err}
    end
  end

  @spec new_char(integer()) :: binary()
  def new_char(code) when is_integer(code), do: <<code::utf8>>
  def new_char(_), do: ""

  @spec basics_compare(term(), term()) :: -1 | 0 | 1
  def basics_compare(a, b) when is_binary(a) and is_binary(b) do
    cond do
      a < b -> -1
      a > b -> 1
      true -> 0
    end
  end

  def basics_compare(a, b) when is_number(a) and is_number(b) do
    cond do
      a < b -> -1
      a > b -> 1
      true -> 0
    end
  end

  def basics_compare(a, b) do
    case {to_number(a), to_number(b)} do
      {{:ok, na}, {:ok, nb}} -> basics_compare(na, nb)
      _ -> 0
    end
  end

  @doc """
  Elm `++` for strings and lists (debugger runtime).
  """
  @spec append(term(), term()) :: term()
  def append(left, right) when is_list(left) and is_list(right), do: left ++ right
  def append(left, right), do: to_string(left) <> to_string(right)

  @doc """
  Apply an Elm-style unary callback; rejects still-curried results from partial application bugs.
  """
  @spec apply1(term(), term()) :: term()
  def apply1(fun, arg) when is_function(fun, 1) do
    case fun.(arg) do
      step when is_function(step, 1) ->
        raise ArgumentError,
              "expected unary Elm callback result, got function still awaiting an argument"

      value ->
        value
    end
  end

  @doc """
  Apply an Elm-style function that may be 2-arity or curried `\\a -> \\b ->`.
  """
  @spec apply2(term(), term(), term()) :: term()
  def apply2(fun, a, b) when is_function(fun, 2), do: fun.(a, b)

  def apply2(fun, a, b) when is_function(fun, 1) do
    case fun.(a) do
      step when is_function(step, 1) -> step.(b)
      other -> raise ArgumentError, "Core.apply2 expected curried step, got: #{inspect(other)}"
    end
  end

  @spec apply3(term(), term(), term(), term()) :: term()
  def apply3(fun, a, b, c) when is_function(fun, 3), do: fun.(a, b, c)

  def apply3(fun, a, b, c) when is_function(fun, 1) do
    case fun.(a) do
      step when is_function(step, 1) ->
        case step.(b) do
          step2 when is_function(step2, 1) -> step2.(c)
          other -> raise ArgumentError, "Core.apply3 expected curried step, got: #{inspect(other)}"
        end

      other ->
        raise ArgumentError, "Core.apply3 expected curried step, got: #{inspect(other)}"
    end
  end

  @spec apply4(term(), term(), term(), term(), term()) :: term()
  def apply4(fun, a, b, c, d) when is_function(fun, 4), do: fun.(a, b, c, d)

  def apply4(fun, a, b, c, d) when is_function(fun, 1) do
    case fun.(a) do
      step when is_function(step, 1) ->
        case step.(b) do
          step2 when is_function(step2, 1) ->
            case step2.(c) do
              step3 when is_function(step3, 1) -> step3.(d)
              other -> raise ArgumentError, "Core.apply4 expected curried step, got: #{inspect(other)}"
            end

          other ->
            raise ArgumentError, "Core.apply4 expected curried step, got: #{inspect(other)}"
        end

      other ->
        raise ArgumentError, "Core.apply4 expected curried step, got: #{inspect(other)}"
    end
  end

  @doc "Elm `List.map` with unary or partially applied callbacks."
  @spec map(term(), list()) :: list()
  def map(fun, list) when is_list(list) do
    Enum.map(list, fn item -> apply1(fun, item) end)
  end

  @doc "Elm `List.filter`."
  @spec filter(term(), list()) :: list()
  def filter(fun, list) when is_list(list) do
    Enum.filter(list, fn item -> apply1(fun, item) end)
  end

  @doc "Elm `List.any`."
  @spec any(term(), list()) :: boolean()
  def any(fun, list) when is_list(list) do
    Enum.any?(list, fn item -> apply1(fun, item) end)
  end

  @doc "Elm `List.filterMap`."
  @spec filter_map(term(), list()) :: list()
  def filter_map(fun, list) when is_list(list) do
    Enum.flat_map(list, fn item ->
      case apply1(fun, item) do
        :Nothing -> []
        {:Just, value} -> [value]
        %{"ctor" => "Nothing"} -> []
        %{"ctor" => "Just", "args" => [value]} -> [value]
        _ -> []
      end
    end)
  end

  @doc "Elm `List.concatMap`."
  @spec concat_map(term(), list()) :: list()
  def concat_map(fun, list) when is_list(list) do
    Enum.flat_map(list, fn item ->
      case apply1(fun, item) do
        sublist when is_list(sublist) -> sublist
        _ -> []
      end
    end)
  end

  @doc "Elm `List.sortBy`."
  @spec sort_by(term(), list()) :: list()
  def sort_by(fun, list) when is_list(list) do
    Enum.sort_by(list, fn item -> apply1(fun, item) end)
  end

  @doc """
  Elm `List.foldl` — left fold with curried or 2-arity callbacks.
  """
  @spec foldl(term(), term(), list()) :: term()
  def foldl(fun, acc, list) when is_list(list) do
    Enum.reduce(list, acc, fn item, acc0 -> apply2(fun, item, acc0) end)
  end

  @doc """
  Elm `List.foldr` — right fold with curried or 2-arity callbacks.
  """
  @spec foldr(term(), term(), list()) :: term()
  def foldr(fun, acc, list) when is_list(list) do
    Enum.reduce(Enum.reverse(list), acc, fn item, acc0 -> apply2(fun, item, acc0) end)
  end

  @doc "Elm `List.repeat`."
  @spec list_repeat(integer(), term()) :: list()
  def list_repeat(n, value) when is_integer(n) and n >= 0, do: List.duplicate(value, n)

  @doc "Elm `List.member`."
  @spec member(term(), list()) :: boolean()
  def member(value, list) when is_list(list), do: value in list

  @doc "Elm `List.all`."
  @spec all(term(), list()) :: boolean()
  def all(fun, list) when is_list(list) do
    Enum.all?(list, fn item -> apply1(fun, item) end)
  end

  @doc "Elm `List.sort`."
  @spec sort(list()) :: list()
  def sort(list) when is_list(list), do: Enum.sort(list)

  @doc "Elm `List.product`."
  @spec list_product(list()) :: number()
  def list_product(list) when is_list(list) do
    Enum.reduce(list, 1, fn item, acc ->
      case to_number(item) do
        {:ok, n} -> acc * n
        :error -> acc
      end
    end)
  end

  @doc "Elm `List.maximum`."
  @spec list_maximum(list()) :: term()
  def list_maximum([]), do: :Nothing
  def list_maximum([first | rest]) do
    Enum.reduce(rest, first, fn item, acc ->
      if basics_compare(item, acc) == 1, do: item, else: acc
    end)
    |> just_wrap()
  end

  @doc "Elm `List.minimum`."
  @spec list_minimum(list()) :: term()
  def list_minimum([]), do: :Nothing
  def list_minimum([first | rest]) do
    Enum.reduce(rest, first, fn item, acc ->
      if basics_compare(item, acc) == -1, do: item, else: acc
    end)
    |> just_wrap()
  end

  @doc "Elm `List.sum`."
  @spec list_sum(list()) :: number()
  def list_sum(list) when is_list(list) do
    Enum.reduce(list, 0, fn item, acc ->
      case to_number(item) do
        {:ok, n} -> acc + n
        :error -> acc
      end
    end)
  end

  @doc "Elm `List.sortWith` — comparison returns `Order` (LT/EQ/GT)."
  @spec sort_with(term(), list()) :: list()
  def sort_with(fun, list) when is_list(list) do
    Enum.sort(list, fn a, b ->
      case apply2(fun, a, b) do
        order -> compare_order_value(order) != :gt
      end
    end)
  rescue
    _ -> Enum.sort(list)
  end

  @doc """
  Elm `List.indexedMap` — supports 2-arity functions and curried `\\i -> \\v ->` lambdas.
  """
  @spec indexed_map(term(), list()) :: list()
  def indexed_map(fun, list) when is_function(fun, 2) and is_list(list) do
    Enum.map(Enum.with_index(list), fn {item, index} -> fun.(index, item) end)
  end

  def indexed_map(fun, list) when is_function(fun, 1) and is_list(list) do
    Enum.map(Enum.with_index(list), fn {item, index} -> apply2(fun, index, item) end)
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

  defp normalize_maybe(:Nothing), do: :Nothing
  defp normalize_maybe({:Just, _} = value), do: value
  defp normalize_maybe(%{"ctor" => _} = value), do: value
  defp normalize_maybe(_), do: :Nothing

  defp to_number(n) when is_integer(n), do: {:ok, n}
  defp to_number(n) when is_float(n), do: {:ok, n}
  defp to_number(%{"ctor" => "Float", "args" => [f]}), do: {:ok, f * 1.0}
  defp to_number(%{ctor: :Float, args: [f]}), do: {:ok, f * 1.0}
  defp to_number(_), do: :error

end
