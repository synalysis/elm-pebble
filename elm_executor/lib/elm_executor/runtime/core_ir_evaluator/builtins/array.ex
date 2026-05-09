defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Array do
  @moduledoc false

  @spec eval(String.t(), term(), map()) :: {:ok, term()} | :no_builtin | {:error, term()}
  def eval("empty", [], _ops), do: {:ok, []}
  def eval("singleton", [value], _ops), do: {:ok, [value]}
  def eval("fromlist", [xs], _ops) when is_list(xs), do: {:ok, xs}
  def eval("tolist", [xs], _ops) when is_list(xs), do: {:ok, xs}

  def eval("repeat", [n, value], _ops) when is_integer(n) and n >= 0,
    do: {:ok, List.duplicate(value, n)}

  def eval("length", [xs], _ops) when is_list(xs), do: {:ok, length(xs)}
  def eval("isempty", [xs], _ops) when is_list(xs), do: {:ok, xs == []}

  def eval("slice", [start, stop, xs], ops)
      when is_integer(start) and is_integer(stop) and is_list(xs),
      do: {:ok, ops.slice.(xs, start, stop)}

  def eval("foldl", [fun, init, xs], ops) when is_list(xs), do: ops.foldl.(fun, init, xs)
  def eval("foldr", [fun, init, xs], ops) when is_list(xs), do: ops.foldr.(fun, init, xs)
  def eval("initialize", [n, fun], ops) when is_integer(n) and n >= 0, do: ops.initialize.(n, fun)
  def eval("map", [fun, xs], ops) when is_list(xs), do: ops.map.(fun, xs)
  def eval("indexedmap", [fun, xs], ops) when is_list(xs), do: ops.indexed_map.(fun, xs)

  def eval("get", [idx, xs], ops) when is_integer(idx) and is_list(xs),
    do: {:ok, ops.get.(xs, idx)}

  def eval("set", [idx, value, xs], ops) when is_integer(idx) and is_list(xs),
    do: {:ok, ops.set.(xs, idx, value)}

  def eval("push", [value, xs], _ops) when is_list(xs), do: {:ok, xs ++ [value]}

  def eval("append", [left, right], _ops) when is_list(left) and is_list(right),
    do: {:ok, left ++ right}

  def eval(_function_name, _values, _ops), do: :no_builtin
end
