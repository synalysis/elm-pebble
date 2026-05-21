defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Cmd do
  @moduledoc false

  alias ElmExecutor.Runtime.CoreIREvaluator.Types, as: EvalTypes
  @spec eval(String.t(), EvalTypes.runtime_values()) :: EvalTypes.builtin_eval_result()
  def eval("none", []), do: {:ok, %{"kind" => "cmd.none", "commands" => []}}

  def eval("batch", [commands]) when is_list(commands),
    do: {:ok, %{"kind" => "cmd.batch", "commands" => commands}}

  def eval("map", [_fun, command]), do: {:ok, command}
  def eval(_function_name, _values), do: :no_builtin
end
