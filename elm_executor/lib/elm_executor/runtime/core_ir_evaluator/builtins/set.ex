defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Set do
  @moduledoc false

  @spec eval(String.t(), term(), map()) :: {:ok, term()} | :no_builtin | {:error, term()}
  def eval("empty", [], _ops), do: {:ok, []}
  def eval("singleton", [value], _ops), do: {:ok, [value]}
  def eval("fromlist", [items], _ops) when is_list(items), do: {:ok, normalize(items)}
  def eval("tolist", [items], _ops) when is_list(items), do: {:ok, normalize(items)}
  def eval("isEmpty", [items], _ops) when is_list(items), do: {:ok, items == []}
  def eval("isempty", [items], _ops) when is_list(items), do: {:ok, items == []}
  def eval("size", [items], _ops) when is_list(items), do: {:ok, length(normalize(items))}

  def eval("member", [value, items], _ops) when is_list(items),
    do: {:ok, Enum.member?(items, value)}

  def eval("insert", [value, items], _ops) when is_list(items),
    do: {:ok, normalize([value | items])}

  def eval("remove", [value, items], _ops) when is_list(items),
    do: {:ok, Enum.reject(items, &(&1 == value))}

  def eval("union", [left, right], _ops) when is_list(left) and is_list(right),
    do: {:ok, normalize(left ++ right)}

  def eval("intersect", [left, right], _ops) when is_list(left) and is_list(right),
    do: {:ok, left |> normalize() |> Enum.filter(&Enum.member?(right, &1))}

  def eval("diff", [left, right], _ops) when is_list(left) and is_list(right),
    do: {:ok, left |> normalize() |> Enum.reject(&Enum.member?(right, &1))}

  def eval("map", [fun, items], ops) when is_list(items), do: map_set(fun, items, ops)

  def eval("foldl", [fun, init, items], ops) when is_list(items),
    do: fold_set(fun, init, items, ops, :asc)

  def eval("foldr", [fun, init, items], ops) when is_list(items),
    do: fold_set(fun, init, items, ops, :desc)

  def eval("filter", [fun, items], ops) when is_list(items), do: filter_set(fun, items, ops)
  def eval("partition", [fun, items], ops) when is_list(items), do: partition_set(fun, items, ops)
  def eval(_function_name, _values, _ops), do: :no_builtin

  defp normalize(items), do: items |> Enum.uniq() |> Enum.sort()

  defp map_set(fun, items, ops) do
    items
    |> normalize()
    |> Enum.map(fn value -> ops.call.(fun, [value]) end)
    |> collect_ok()
    |> case do
      {:ok, mapped} -> {:ok, normalize(mapped)}
      error -> error
    end
  end

  defp fold_set(fun, init, items, ops, order) do
    values = normalize(items)
    values = if order == :desc, do: Enum.reverse(values), else: values

    Enum.reduce_while(values, {:ok, init}, fn value, {:ok, acc} ->
      case ops.call.(fun, [value, acc]) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp filter_set(fun, items, ops) do
    items
    |> normalize()
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case ops.call.(fun, [value]) do
        {:ok, true} -> {:cont, {:ok, [value | acc]}}
        {:ok, _} -> {:cont, {:ok, acc}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, kept} -> {:ok, normalize(kept)}
      error -> error
    end
  end

  defp partition_set(fun, items, ops) do
    items
    |> normalize()
    |> Enum.reduce_while({:ok, {[], []}}, fn value, {:ok, {yes, no}} ->
      case ops.call.(fun, [value]) do
        {:ok, true} -> {:cont, {:ok, {[value | yes], no}}}
        {:ok, _} -> {:cont, {:ok, {yes, [value | no]}}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, {yes, no}} -> {:ok, {normalize(yes), normalize(no)}}
      error -> error
    end
  end

  defp collect_ok(results) do
    Enum.reduce_while(results, {:ok, []}, fn
      {:ok, value}, {:ok, acc} -> {:cont, {:ok, [value | acc]}}
      {:error, reason}, _acc -> {:halt, {:error, reason}}
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end
end
