defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Empty do
  @moduledoc false

  alias ElmExecutor.Runtime.CoreIREvaluator.Types, as: EvalTypes
  @spec eval(String.t(), EvalTypes.runtime_values(), EvalTypes.ops_context()) :: :no_builtin
  def eval(_function_name, _values, _ops \\ %{}), do: :no_builtin
end
