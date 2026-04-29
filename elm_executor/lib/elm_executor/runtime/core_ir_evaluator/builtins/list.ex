defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.List do
  @moduledoc false

  @spec eval(String.t(), term(), map()) :: {:ok, term()} | :no_builtin | {:error, term()}
  def eval("map", [fun, subject], ops), do: ops.map_dispatch.(fun, subject)

  def eval("map2", [fun, xs, ys], ops) when is_list(xs) and is_list(ys),
    do: ops.list_map2.(fun, xs, ys)

  def eval("reverse", [xs], _ops) when is_list(xs), do: {:ok, Enum.reverse(xs)}

  def eval("append", [xs, ys], _ops) when is_list(xs) and is_list(ys), do: {:ok, xs ++ ys}
  def eval("cons", [head, tail], _ops) when is_list(tail), do: {:ok, [head | tail]}

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
end
