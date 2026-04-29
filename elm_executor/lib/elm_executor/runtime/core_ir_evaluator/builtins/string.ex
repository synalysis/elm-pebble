defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.String do
  @moduledoc false

  alias ElmExecutor.Runtime.CoreIREvaluator.Value.String, as: StringValue

  @spec eval(String.t(), term()) :: {:ok, term()} | :no_builtin
  def eval("append", [a, b]) when is_binary(a) and is_binary(b), do: {:ok, a <> b}
  def eval("fromint", [value]) when is_integer(value), do: {:ok, Integer.to_string(value)}

  def eval("fromfloat", [value]) when is_number(value),
    do: {:ok, StringValue.float_to_elm_string(value)}

  def eval(_function_name, _values), do: :no_builtin
end
