defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Cmd do
  @moduledoc false

  @spec eval(String.t(), term()) :: {:ok, term()} | :no_builtin
  def eval("none", []), do: {:ok, %{"kind" => "cmd.none", "commands" => []}}

  def eval("batch", [commands]) when is_list(commands),
    do: {:ok, %{"kind" => "cmd.batch", "commands" => commands}}

  def eval("map", [_fun, command]), do: {:ok, command}
  def eval(_function_name, _values), do: :no_builtin
end
