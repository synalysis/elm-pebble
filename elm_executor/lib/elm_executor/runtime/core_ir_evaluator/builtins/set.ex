defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Set do
  @moduledoc false

  @spec eval(String.t(), term()) :: {:ok, term()} | :no_builtin
  def eval("fromlist", [items]) when is_list(items),
    do: {:ok, items |> Enum.uniq() |> Enum.sort()}

  def eval("tolist", [items]) when is_list(items), do: {:ok, items}
  def eval(_function_name, _values), do: :no_builtin
end
