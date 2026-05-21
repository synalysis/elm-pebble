defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Debug do
  @moduledoc false

  alias ElmExecutor.Runtime.CoreIREvaluator.Types, as: EvalTypes
  @spec eval(String.t(), EvalTypes.runtime_values(), EvalTypes.ops_context()) :: EvalTypes.builtin_eval_result()
  def eval("tostring", [value], ops), do: {:ok, ops.to_string.(value)}
  def eval(_function_name, _values, _ops), do: :no_builtin
end
