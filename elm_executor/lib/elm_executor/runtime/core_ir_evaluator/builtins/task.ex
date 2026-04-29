defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Task do
  @moduledoc false

  @spec eval(String.t(), term(), map()) :: {:ok, term()} | :no_builtin | {:error, term()}
  def eval("map2", [a, b, c], ops), do: ops.map2_dispatch.(a, b, c)
  def eval(_function_name, _values, _ops), do: :no_builtin
end
