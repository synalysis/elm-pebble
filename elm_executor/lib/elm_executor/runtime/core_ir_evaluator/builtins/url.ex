defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Url do
  @moduledoc false

  alias ElmExecutor.Runtime.CoreIREvaluator.Types, as: EvalTypes
  @spec eval(String.t(), EvalTypes.runtime_values()) :: EvalTypes.builtin_eval_result()
  def eval("percentencode", [value]) when is_binary(value) do
    {:ok, URI.encode(value, &URI.char_unreserved?/1)}
  end

  def eval("percentdecode", [value]) when is_binary(value) do
    try do
      {:ok, maybe_ctor({:just, URI.decode(value)})}
    rescue
      _ -> {:ok, maybe_ctor(:nothing)}
    end
  end

  def eval(_function_name, _values), do: :no_builtin

  @spec maybe_ctor(EvalTypes.maybe_ctor_input()) :: EvalTypes.ctor_map()
  defp maybe_ctor({:just, value}), do: %{"ctor" => "Just", "args" => [value]}
  defp maybe_ctor(:nothing), do: %{"ctor" => "Nothing", "args" => []}
end
