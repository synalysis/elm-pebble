defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.List do
  @moduledoc false

  @spec eval(String.t(), term(), map()) :: {:ok, term()} | :no_builtin | {:error, term()}
  def eval("map", [fun, subject], ops), do: ops.map_dispatch.(fun, subject)

  def eval("map2", [fun, xs, ys], ops) when is_list(xs) and is_list(ys),
    do: ops.list_map2.(fun, xs, ys)

  def eval("map3", [fun, xs, ys, zs], ops) when is_list(xs) and is_list(ys) and is_list(zs),
    do: map_n(fun, [xs, ys, zs], ops)

  def eval("map4", [fun, a, b, c, d], ops)
      when is_list(a) and is_list(b) and is_list(c) and is_list(d),
      do: map_n(fun, [a, b, c, d], ops)

  def eval("map5", [fun, a, b, c, d, e], ops)
      when is_list(a) and is_list(b) and is_list(c) and is_list(d) and is_list(e),
      do: map_n(fun, [a, b, c, d, e], ops)

  def eval("indexedmap", [fun, xs], ops) when is_list(xs), do: ops.indexed_map.(fun, xs)
  def eval("concatmap", [fun, xs], ops) when is_list(xs), do: ops.concat_map.(fun, xs)
  def eval("reverse", [xs], _ops) when is_list(xs), do: {:ok, Enum.reverse(xs)}
  def eval("append", [xs, ys], _ops) when is_list(xs) and is_list(ys), do: {:ok, xs ++ ys}
  def eval("concat", [xss], _ops) when is_list(xss), do: {:ok, Enum.flat_map(xss, &List.wrap/1)}
  def eval("cons", [head, tail], _ops) when is_list(tail), do: {:ok, [head | tail]}
  def eval("isempty", [xs], _ops) when is_list(xs), do: {:ok, xs == []}
  def eval("singleton", [value], _ops), do: {:ok, [value]}

  def eval("repeat", [n, value], _ops) when is_integer(n) and n >= 0,
    do: {:ok, List.duplicate(value, n)}

  def eval("range", [start, stop], _ops) when is_integer(start) and is_integer(stop),
    do: {:ok, if(start > stop, do: [], else: Enum.to_list(start..stop))}

  def eval("take", [n, xs], _ops) when is_integer(n) and is_list(xs),
    do: {:ok, Enum.take(xs, max(n, 0))}

  def eval("drop", [n, xs], _ops) when is_integer(n) and is_list(xs),
    do: {:ok, Enum.drop(xs, max(n, 0))}

  def eval("length", [xs], _ops) when is_list(xs), do: {:ok, length(xs)}
  def eval("member", [x, xs], _ops) when is_list(xs), do: {:ok, Enum.member?(xs, x)}
  def eval("tail", [xs], ops) when is_list(xs), do: ops.tail.(xs)

  def eval("sum", [xs], _ops) when is_list(xs),
    do: {:ok, Enum.reduce(xs, 0, fn x, acc -> if is_number(x), do: acc + x, else: acc end)}

  def eval("product", [xs], _ops),
    do: {:ok, Enum.reduce(xs, 1, fn x, acc -> if is_number(x), do: acc * x, else: acc end)}

  def eval("maximum", [xs], ops) when is_list(xs), do: ops.maximum.(xs)
  def eval("minimum", [xs], ops) when is_list(xs), do: ops.minimum.(xs)
  def eval("head", [xs], ops) when is_list(xs), do: ops.head.(xs)
  def eval("all", [fun, xs], ops) when is_list(xs), do: ops.all.(fun, xs)
  def eval("any", [fun, xs], ops) when is_list(xs), do: ops.any.(fun, xs)
  def eval("partition", [fun, xs], ops) when is_list(xs), do: ops.partition.(fun, xs)
  def eval("sort", [xs], _ops) when is_list(xs), do: {:ok, Enum.sort(xs)}
  def eval("sortby", [fun, xs], ops) when is_list(xs), do: ops.sort_by.(fun, xs)
  def eval("sortwith", [fun, xs], ops) when is_list(xs), do: ops.sort_with.(fun, xs)
  def eval("intersperse", [sep, xs], _ops) when is_list(xs), do: {:ok, intersperse(xs, sep)}
  def eval("unzip", [pairs], _ops) when is_list(pairs), do: {:ok, unzip(pairs)}

  def eval("append", [xs], _ops) when is_list(xs),
    do: {:ok, {:builtin_partial, "List.append", [xs]}}

  def eval("foldl", [fun, init, xs], ops) when is_list(xs), do: ops.foldl.(fun, init, xs)
  def eval("foldr", [fun, init, xs], ops) when is_list(xs), do: ops.foldr.(fun, init, xs)
  def eval("all", [fun], _ops), do: {:ok, {:builtin_partial, "List.all", [fun]}}
  def eval("any", [fun], _ops), do: {:ok, {:builtin_partial, "List.any", [fun]}}
  def eval("filter", [fun, xs], ops) when is_list(xs), do: ops.filter.(fun, xs)
  def eval("map", [fun], _ops), do: {:ok, {:builtin_partial, "List.map", [fun]}}
  def eval("filter", [fun], _ops), do: {:ok, {:builtin_partial, "List.filter", [fun]}}
  def eval("foldl", [fun, init], _ops), do: {:ok, {:builtin_partial, "List.foldl", [fun, init]}}
  def eval("foldr", [fun, init], _ops), do: {:ok, {:builtin_partial, "List.foldr", [fun, init]}}
  def eval(_function_name, _values, _ops), do: :no_builtin

  defp map_n(fun, lists, ops) do
    lists
    |> Enum.zip()
    |> Enum.map(fn tuple -> ops.call.(fun, Tuple.to_list(tuple)) end)
    |> collect_ok()
  end

  defp intersperse([], _sep), do: []
  defp intersperse([x], _sep), do: [x]
  defp intersperse([x | rest], sep), do: [x, sep | intersperse(rest, sep)]

  defp unzip(pairs) do
    pairs
    |> Enum.map(&pair_to_tuple/1)
    |> Enum.reduce({[], []}, fn
      {a, b}, {as, bs} -> {[a | as], [b | bs]}
      :error, acc -> acc
    end)
    |> then(fn {as, bs} -> {Enum.reverse(as), Enum.reverse(bs)} end)
  end

  defp pair_to_tuple({a, b}), do: {a, b}
  defp pair_to_tuple([a, b]), do: {a, b}
  defp pair_to_tuple(_), do: :error

  defp collect_ok(results) do
    Enum.reduce_while(results, {:ok, []}, fn
      {:ok, value}, {:ok, acc} -> {:cont, {:ok, [value | acc]}}
      {:error, reason}, _acc -> {:halt, {:error, reason}}
      other, _acc -> {:halt, {:error, {:unexpected_result, other}}}
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end
end
