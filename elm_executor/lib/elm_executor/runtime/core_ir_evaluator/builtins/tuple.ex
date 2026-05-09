defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Tuple do
  @moduledoc false

  @spec eval(String.t(), term(), map()) :: {:ok, term()} | :no_builtin | {:error, term()}
  def eval("pair", [a, b], _ops), do: {:ok, {a, b}}
  def eval("first", [{a, _b}], _ops), do: {:ok, a}
  def eval("first", [[a, _b]], _ops), do: {:ok, a}
  def eval("second", [{_a, b}], _ops), do: {:ok, b}
  def eval("second", [[_a, b]], _ops), do: {:ok, b}
  def eval("mapfirst", [fun, pair], ops), do: map_pair(fun, pair, ops, :first)
  def eval("mapsecond", [fun, pair], ops), do: map_pair(fun, pair, ops, :second)
  def eval("mapboth", [f1, f2, pair], ops), do: map_both(f1, f2, pair, ops)
  def eval(_function_name, _values, _ops), do: :no_builtin

  defp map_pair(fun, pair, ops, side) do
    with {:ok, {a, b}} <- tuple_to_pair(pair),
         {:ok, mapped} <- ops.call.(fun, [if(side == :first, do: a, else: b)]) do
      {:ok, if(side == :first, do: {mapped, b}, else: {a, mapped})}
    else
      :error -> :no_builtin
      {:error, reason} -> {:error, reason}
    end
  end

  defp map_both(f1, f2, pair, ops) do
    with {:ok, {a, b}} <- tuple_to_pair(pair),
         {:ok, mapped_a} <- ops.call.(f1, [a]),
         {:ok, mapped_b} <- ops.call.(f2, [b]) do
      {:ok, {mapped_a, mapped_b}}
    else
      :error -> :no_builtin
      {:error, reason} -> {:error, reason}
    end
  end

  defp tuple_to_pair({a, b}), do: {:ok, {a, b}}
  defp tuple_to_pair([a, b]), do: {:ok, {a, b}}
  defp tuple_to_pair(_), do: :error
end
