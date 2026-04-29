defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Result do
  @moduledoc false

  @spec eval(String.t(), term(), map()) :: {:ok, term()} | :no_builtin | {:error, term()}
  def eval("andthen", [fun, result], ops), do: ops.and_then.(fun, result)
  def eval("map2", [a, b, c], ops), do: ops.map2_dispatch.(a, b, c)
  def eval(_function_name, _values, _ops), do: :no_builtin
end
