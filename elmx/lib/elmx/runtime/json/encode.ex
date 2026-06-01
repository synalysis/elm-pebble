defmodule Elmx.Runtime.Json.Encode do
  @moduledoc """
  Minimal `Json.Encode` runtime for companion phone apps (aligned with Core IR json.encode builtins).
  """

  @spec null() :: nil
  def null, do: nil

  @spec int(term()) :: term()
  def int(value) when is_integer(value), do: value
  def int(value), do: value

  @spec float(term()) :: float()
  def float(value) when is_float(value), do: value
  def float(value) when is_integer(value), do: value * 1.0

  @spec bool(term()) :: boolean()
  def bool(true), do: true
  def bool(false), do: false
  def bool(value) when is_boolean(value), do: value

  @spec string(term()) :: String.t()
  def string(value) when is_binary(value), do: value
  def string(value) when is_integer(value), do: Integer.to_string(value)
  def string(value) when is_boolean(value), do: if(value, do: "true", else: "false")
  def string(value) when is_float(value), do: :erlang.float_to_binary(value, [:compact, decimals: 16])
  def string(value), do: to_string(value)

  @spec list(term(), list()) :: list()
  def list(encoder, items) when is_function(encoder, 1) and is_list(items) do
    Enum.map(items, encoder)
  end

  def list(_encoder, items) when is_list(items), do: items
  def list(_encoder, _items), do: []

  @spec object(list()) :: map()
  def object(pairs) when is_list(pairs) do
    Enum.reduce(pairs, %{}, &object_pair/2)
  end

  defp object_pair({key, value}, acc) when is_binary(key), do: Map.put(acc, key, value)
  defp object_pair([key, value], acc) when is_binary(key), do: Map.put(acc, key, value)
  defp object_pair(_pair, acc), do: acc

  @spec dict(term(), list()) :: map()
  def dict(encoder, pairs) when is_list(pairs) do
    pairs
    |> Enum.map(fn
      {key, value} -> {Integer.to_string(key), encoder.(value)}
      [key, value] -> {Integer.to_string(key), encoder.(value)}
    end)
    |> object()
  end

  @spec encode(non_neg_integer(), term()) :: String.t()
  def encode(indent, value) when is_integer(indent) and indent >= 0 do
    opts = if indent > 0, do: [pretty: true], else: []

    case Jason.encode(value, opts) do
      {:ok, encoded} -> encoded
      _ -> "null"
    end
  end
end
