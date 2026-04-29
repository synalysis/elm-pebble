defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Maybe do
  @moduledoc false

  alias ElmExecutor.Runtime.CoreIREvaluator.Value.MaybeResult

  @spec eval(String.t(), term(), map()) :: {:ok, term()} | :no_builtin | {:error, term()}
  def eval("withdefault", [default, maybe_or_result], _ops),
    do: {:ok, MaybeResult.with_default(default, maybe_or_result)}

  def eval("map2", [a, b, c], ops), do: ops.map2_dispatch.(a, b, c)
  def eval(_function_name, _values, _ops), do: :no_builtin
end
