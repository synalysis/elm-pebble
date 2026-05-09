defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Result do
  @moduledoc false

  alias ElmExecutor.Runtime.CoreIREvaluator.Value.MaybeResult

  @spec eval(String.t(), term(), map()) :: {:ok, term()} | :no_builtin | {:error, term()}
  def eval("map", [fun, result], ops), do: ops.map.(fun, result)
  def eval("andthen", [fun, result], ops), do: ops.and_then.(fun, result)
  def eval("map2", [a, b, c], ops), do: ops.map2_dispatch.(a, b, c)
  def eval("maperror", [fun, result], ops), do: result_map_error(fun, result, ops)

  def eval("withdefault", [default, result], _ops),
    do: {:ok, MaybeResult.with_default(default, result)}

  def eval("tomaybe", [result], _ops), do: {:ok, result_to_maybe(result)}
  def eval("frommaybe", [error, maybe], _ops), do: {:ok, maybe_to_result(error, maybe)}
  def eval(_function_name, _values, _ops), do: :no_builtin

  defp result_map_error(fun, result, ops) do
    case MaybeResult.result_value(result) do
      {:ok, value} ->
        {:ok, MaybeResult.result_ctor_like(result, {:ok, value})}

      {:err, error} ->
        case ops.call.(fun, [error]) do
          {:ok, mapped} -> {:ok, MaybeResult.result_ctor_like(result, {:err, mapped})}
          {:error, reason} -> {:error, reason}
        end

      :invalid ->
        :no_builtin
    end
  end

  defp result_to_maybe(result) do
    case MaybeResult.result_value(result) do
      {:ok, value} -> MaybeResult.maybe_ctor({:just, value})
      {:err, _error} -> MaybeResult.maybe_ctor(:nothing)
      :invalid -> MaybeResult.maybe_ctor(:nothing)
    end
  end

  defp maybe_to_result(error, maybe) do
    case MaybeResult.maybe_value(maybe) do
      {:just, value} -> MaybeResult.result_ctor({:ok, value})
      :nothing -> MaybeResult.result_ctor({:err, error})
      :invalid -> MaybeResult.result_ctor({:err, error})
    end
  end
end
