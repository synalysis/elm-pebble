defmodule Elmx.Runtime.Json.Encode do
  @moduledoc """
  Minimal `Json.Encode` runtime for companion phone apps (aligned with Core IR json.encode builtins).
  """

  alias Elmx.Types

  @spec null() :: nil
  def null, do: nil

  @spec int(Types.json_value()) :: number()
  def int(value) when is_integer(value), do: value
  def int(value), do: value

  @spec float(Types.numeric_input()) :: float()
  def float(value) when is_float(value), do: value
  def float(value) when is_integer(value), do: value * 1.0

  @spec bool(boolean()) :: boolean()
  def bool(true), do: true
  def bool(false), do: false

  @spec string(Types.string_like()) :: String.t()
  def string(value) when is_binary(value), do: value
  def string(value) when is_integer(value), do: Integer.to_string(value)
  def string(value) when is_boolean(value), do: if(value, do: "true", else: "false")
  def string(value) when is_float(value), do: :erlang.float_to_binary(value, [:compact, decimals: 16])
  def string(value), do: to_string(value)

  @spec list(Types.elm_hof(), Types.elm_list()) :: [Types.json_value()]
  def list(encoder, items) when is_function(encoder, 1) and is_list(items) do
    Enum.map(items, encoder)
  end

  def list(_encoder, items) when is_list(items), do: items
  def list(_encoder, _items), do: []

  @spec object([Types.json_object_pair()]) :: Types.json_object_value()
  def object(pairs) when is_list(pairs) do
    ordered =
      pairs
      |> Enum.reduce([], fn
        {key, value}, acc when is_binary(key) -> [{key, value} | acc]
        [key, value], acc when is_binary(key) -> [{key, value} | acc]
        _pair, acc -> acc
      end)
      |> Enum.reverse()

    {:elmx_json_object, ordered}
  end

  @spec dict(Types.elm_hof(), Types.elm_dict() | list()) :: Types.json_object_value()
  def dict(encoder, pairs) when is_list(pairs) do
    pairs
    |> Enum.map(fn
      {key, value} -> {Integer.to_string(key), encoder.(value)}
      [key, value] -> {Integer.to_string(key), encoder.(value)}
    end)
    |> object()
  end

  @spec encode(non_neg_integer(), Types.json_value()) :: String.t()
  def encode(indent, value) when is_integer(indent) and indent >= 0 do
    encode_value(value, indent, 0)
  end

  defp encode_value({:elmx_json_object, pairs}, indent, depth) when is_list(pairs) do
    if indent > 0 do
      inner_indent = indent_string(indent, depth + 1)

      "{\n" <>
        Enum.map_join(pairs, ",\n", fn pair ->
          inner_indent <> encode_object_pair(pair, indent, depth + 1)
        end) <>
        "\n" <> indent_string(indent, depth) <> "}"
    else
      "{" <> Enum.map_join(pairs, ",", &encode_object_pair(&1, indent, depth)) <> "}"
    end
  end

  defp encode_value(value, indent, depth) when is_list(value) do
    if indent > 0 do
      inner_indent = indent_string(indent, depth + 1)

      "[\n" <>
        Enum.map_join(value, ",\n", fn item ->
          inner_indent <> encode_value(item, indent, depth + 1)
        end) <>
        "\n" <> indent_string(indent, depth) <> "]"
    else
      "[" <> Enum.map_join(value, ",", &encode_value(&1, indent, depth)) <> "]"
    end
  end

  defp encode_value(value, _indent, _depth) when is_boolean(value) or is_nil(value) or is_number(value) do
    case Jason.encode(value) do
      {:ok, encoded} -> encoded
      _ -> "null"
    end
  end

  defp encode_value(value, _indent, _depth) when is_binary(value) do
    case Jason.encode(value) do
      {:ok, encoded} -> encoded
      _ -> "\"\""
    end
  end

  defp encode_value(value, indent, depth) when is_map(value) do
    case Jason.encode(value, maps: :naive) do
      {:ok, encoded} -> encoded
      _ -> encode_value(object(Map.to_list(value)), indent, depth)
    end
  end

  defp encode_value(_value, _indent, _depth), do: "null"

  defp encode_object_pair({key, value}, indent, depth) when is_binary(key) do
    case Jason.encode(key) do
      {:ok, encoded_key} -> encoded_key <> ":" <> encode_value(value, indent, depth)
      _ -> "\"\":" <> encode_value(value, indent, depth)
    end
  end

  defp indent_string(_indent, depth) when depth <= 0, do: ""
  defp indent_string(indent, depth) when indent > 0 and depth > 0, do: String.duplicate(" ", indent * depth)
end
