defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Parser do
  @moduledoc false

  alias ElmExecutor.Runtime.CoreIREvaluator.Types, as: EvalTypes
  @spec eval(String.t(), EvalTypes.runtime_values(), EvalTypes.ops_context()) :: EvalTypes.builtin_eval_result()
  def eval("run", [parser, source], ops) when is_binary(source), do: ops.call.(parser, [source])
  def eval(_function_name, _values, _ops), do: :no_builtin
end
