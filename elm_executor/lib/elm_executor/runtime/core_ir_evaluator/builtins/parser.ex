defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Parser do
  @moduledoc false

  @spec eval(String.t(), term(), map()) :: {:ok, term()} | :no_builtin | {:error, term()}
  def eval("run", [parser, source], ops) when is_binary(source), do: ops.call.(parser, [source])
  def eval(_function_name, _values, _ops), do: :no_builtin
end
