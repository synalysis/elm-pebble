defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Basics do
  @moduledoc false

  @spec eval(String.t(), term(), map()) :: {:ok, term()} | :no_builtin | {:error, term()}
  def eval("map2", [a, b, c], ops), do: ops.map2_dispatch.(a, b, c)
  def eval("negate", [value], _ops) when is_number(value), do: {:ok, -value}
  def eval(_function_name, _values, _ops), do: :no_builtin
end
