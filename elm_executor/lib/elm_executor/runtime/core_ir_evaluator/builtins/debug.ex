defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Debug do
  @moduledoc false

  @spec eval(String.t(), term(), map()) :: {:ok, term()} | :no_builtin
  def eval("tostring", [value], ops), do: {:ok, ops.to_string.(value)}
  def eval(_function_name, _values, _ops), do: :no_builtin
end
