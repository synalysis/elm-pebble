defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Empty do
  @moduledoc false

  @spec eval(String.t(), term(), map()) :: :no_builtin
  def eval(_function_name, _values, _ops \\ %{}), do: :no_builtin
end
