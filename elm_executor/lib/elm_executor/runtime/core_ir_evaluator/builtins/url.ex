defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Url do
  @moduledoc false

  @spec eval(String.t(), term()) :: {:ok, term()} | :no_builtin
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

  @spec maybe_ctor({:just, term()} | :nothing) :: map()
  defp maybe_ctor({:just, value}), do: %{"ctor" => "Just", "args" => [value]}
  defp maybe_ctor(:nothing), do: %{"ctor" => "Nothing", "args" => []}
end
