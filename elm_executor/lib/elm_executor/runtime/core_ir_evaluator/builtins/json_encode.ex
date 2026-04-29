defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.JsonEncode do
  @moduledoc false

  @spec eval(String.t(), term(), map()) :: {:ok, term()} | :no_builtin | {:error, term()}
  def eval("string", [value], _ops) when is_binary(value), do: {:ok, value}
  def eval("int", [value], _ops) when is_integer(value), do: {:ok, value}
  def eval("float", [value], _ops) when is_number(value), do: {:ok, value * 1.0}
  def eval("bool", [value], _ops) when is_boolean(value), do: {:ok, value}
  def eval("null", [_value], _ops), do: {:ok, nil}

  def eval("list", [encoder, items], ops) when is_list(items) do
    items
    |> Enum.map(&ops.call_encoder.(encoder, &1))
    |> ops.collect_ok.()
  end

  def eval("object", [pairs], _ops) when is_list(pairs) do
    mapped =
      pairs
      |> Enum.map(fn
        {k, v} when is_binary(k) -> {k, v}
        [k, v] when is_binary(k) -> {k, v}
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    {:ok, mapped}
  end

  def eval("encode", [indent, value], _ops) when is_integer(indent) and indent >= 0 do
    case Jason.encode(value) do
      {:ok, encoded} -> {:ok, encoded}
      _ -> {:ok, "null"}
    end
  end

  def eval(_function_name, _values, _ops), do: :no_builtin
end
