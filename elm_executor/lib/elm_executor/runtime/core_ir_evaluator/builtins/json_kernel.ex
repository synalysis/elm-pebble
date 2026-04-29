defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.JsonKernel do
  @moduledoc false

  @spec eval(String.t(), list(), map()) :: term()
  def eval(json_name, values, ops)
      when is_binary(json_name) and is_list(values) and is_map(ops) do
    case {json_name, values} do
      {"run", []} ->
        {:ok, {:builtin_partial, "Elm.Kernel.Json.run", []}}

      {"run", [decoder]} ->
        {:ok, {:builtin_partial, "Elm.Kernel.Json.run", [decoder]}}

      {"run", [decoder, value]} ->
        run_decoder(decoder, value, ops)

      {"runonstring", []} ->
        {:ok, {:builtin_partial, "Elm.Kernel.Json.runOnString", []}}

      {"runonstring", [decoder]} ->
        {:ok, {:builtin_partial, "Elm.Kernel.Json.runOnString", [decoder]}}

      {"runonstring", [decoder, text]} when is_binary(text) ->
        run_decoder_on_string(decoder, text, ops)

      {"decodebool", []} ->
        {:ok, {:json_decoder, :bool}}

      {"decodeint", []} ->
        {:ok, {:json_decoder, :int}}

      {"decodefloat", []} ->
        {:ok, {:json_decoder, :float}}

      {"decodestring", []} ->
        {:ok, {:json_decoder, :string}}

      {"decodevalue", []} ->
        {:ok, {:json_decoder, :value}}

      {"decodelist", [decoder]} ->
        {:ok, {:json_decoder, {:list, decoder}}}

      {"decodearray", [decoder]} ->
        {:ok, {:json_decoder, {:array, decoder}}}

      {"decodekeyvaluepairs", [decoder]} ->
        {:ok, {:json_decoder, {:key_value_pairs, decoder}}}

      {"decodefield", [field]} when is_binary(field) ->
        {:ok, {:builtin_partial, "Elm.Kernel.Json.decodeField", [field]}}

      {"decodefield", [field, decoder]} when is_binary(field) ->
        {:ok, {:json_decoder, {:field, field, decoder}}}

      {"decodeindex", [index]} when is_integer(index) ->
        {:ok, {:builtin_partial, "Elm.Kernel.Json.decodeIndex", [index]}}

      {"decodeindex", [index, decoder]} when is_integer(index) ->
        {:ok, {:json_decoder, {:index, index, decoder}}}

      {"decodenull", [value]} ->
        {:ok, {:json_decoder, {:null, value}}}

      {"oneof", [decoders]} when is_list(decoders) ->
        {:ok, {:json_decoder, {:one_of, decoders}}}

      {"succeed", [value]} ->
        {:ok, {:json_decoder, {:succeed, value}}}

      {"fail", [message]} when is_binary(message) ->
        {:ok, {:json_decoder, {:fail, message}}}

      {"andthen", [fun]} ->
        {:ok, {:builtin_partial, "Elm.Kernel.Json.andThen", [fun]}}

      {"andthen", [fun, decoder]} ->
        {:ok, {:json_decoder, {:and_then, fun, decoder}}}

      {"map1", [fun, d1]} ->
        {:ok, {:json_decoder, {:map, fun, [d1]}}}

      {"map2", [fun, d1, d2]} ->
        {:ok, {:json_decoder, {:map, fun, [d1, d2]}}}

      {"map3", [fun, d1, d2, d3]} ->
        {:ok, {:json_decoder, {:map, fun, [d1, d2, d3]}}}

      {"map4", [fun, d1, d2, d3, d4]} ->
        {:ok, {:json_decoder, {:map, fun, [d1, d2, d3, d4]}}}

      {"map5", [fun, d1, d2, d3, d4, d5]} ->
        {:ok, {:json_decoder, {:map, fun, [d1, d2, d3, d4, d5]}}}

      {"map6", [fun, d1, d2, d3, d4, d5, d6]} ->
        {:ok, {:json_decoder, {:map, fun, [d1, d2, d3, d4, d5, d6]}}}

      {"map7", [fun, d1, d2, d3, d4, d5, d6, d7]} ->
        {:ok, {:json_decoder, {:map, fun, [d1, d2, d3, d4, d5, d6, d7]}}}

      {"map8", [fun, d1, d2, d3, d4, d5, d6, d7, d8]} ->
        {:ok, {:json_decoder, {:map, fun, [d1, d2, d3, d4, d5, d6, d7, d8]}}}

      _ ->
        :no_builtin
    end
  end

  @spec run_decoder_on_string(term(), term(), map()) :: term()
  def run_decoder_on_string(decoder, text, ops) when is_binary(text) and is_map(ops) do
    case Jason.decode(text) do
      {:ok, value} -> run_decoder(decoder, value, ops)
      {:error, _reason} -> {:ok, ops.result_ctor.({:err, "invalid json"})}
    end
  end

  @spec run_decoder(term(), term(), map()) :: term()
  def run_decoder(decoder, value, ops) when is_map(ops) do
    case decode(decoder, value, ops) do
      {:ok, decoded} -> {:ok, ops.result_ctor.({:ok, decoded})}
      {:error, reason} -> {:ok, ops.result_ctor.({:err, reason})}
    end
  end

  @spec decode(term(), term(), map()) :: term()
  def decode({:json_decoder, :bool}, value, _ops) when is_boolean(value), do: {:ok, value}
  def decode({:json_decoder, :int}, value, _ops) when is_integer(value), do: {:ok, value}
  def decode({:json_decoder, :float}, value, _ops) when is_number(value), do: {:ok, value}
  def decode({:json_decoder, :string}, value, _ops) when is_binary(value), do: {:ok, value}
  def decode({:json_decoder, :value}, value, _ops), do: {:ok, value}
  def decode({:json_decoder, {:succeed, v}}, _value, _ops), do: {:ok, v}
  def decode({:json_decoder, {:fail, msg}}, _value, _ops), do: {:error, msg}
  def decode({:json_decoder, {:null, v}}, nil, _ops), do: {:ok, v}
  def decode({:json_decoder, {:null, _v}}, _value, _ops), do: {:error, "expected null"}

  def decode({:json_decoder, {:list, decoder}}, value, ops) when is_list(value) do
    value
    |> Enum.map(&decode(decoder, &1, ops))
    |> ops.collect_ok.()
  end

  def decode({:json_decoder, {:array, decoder}}, value, ops) when is_list(value) do
    value
    |> Enum.map(&decode(decoder, &1, ops))
    |> ops.collect_ok.()
  end

  def decode({:json_decoder, {:field, field, decoder}}, value, ops)
      when is_binary(field) and is_map(value) do
    if Map.has_key?(value, field) do
      decode(decoder, Map.get(value, field), ops)
    else
      {:error, "missing field"}
    end
  end

  def decode({:json_decoder, {:index, index, decoder}}, value, ops)
      when is_integer(index) and is_list(value) do
    if index >= 0 and index < length(value) do
      decode(decoder, Enum.at(value, index), ops)
    else
      {:error, "index out of range"}
    end
  end

  def decode({:json_decoder, {:key_value_pairs, decoder}}, value, ops) when is_map(value) do
    value
    |> Enum.sort_by(fn {k, _v} -> k end)
    |> Enum.map(fn {k, v} ->
      case decode(decoder, v, ops) do
        {:ok, decoded} -> {:ok, {k, decoded}}
        {:error, reason} -> {:error, reason}
      end
    end)
    |> ops.collect_ok.()
  end

  def decode({:json_decoder, {:one_of, decoders}}, value, ops) when is_list(decoders) do
    Enum.reduce_while(decoders, {:error, "oneOf failed"}, fn decoder, _acc ->
      case decode(decoder, value, ops) do
        {:ok, decoded} -> {:halt, {:ok, decoded}}
        {:error, _} -> {:cont, {:error, "oneOf failed"}}
      end
    end)
  end

  def decode({:json_decoder, {:and_then, fun, decoder}}, value, ops) do
    with {:ok, first} <- decode(decoder, value, ops),
         {:ok, next_decoder} <- ops.call.(fun, [first]),
         {:ok, decoded} <- decode(next_decoder, value, ops) do
      {:ok, decoded}
    end
  end

  def decode({:json_decoder, {:map, fun, decoders}}, value, ops) when is_list(decoders) do
    with {:ok, decoded_values} <- decode_all(decoders, value, ops),
         {:ok, mapped} <- ops.call.(fun, decoded_values) do
      {:ok, mapped}
    end
  end

  def decode({:json_decoder, _spec}, _value, _ops), do: {:error, "decoder mismatch"}
  def decode(_decoder, _value, _ops), do: {:error, "not a decoder"}

  @spec decode_all([term()], term(), map()) :: term()
  defp decode_all(decoders, value, ops) when is_list(decoders) do
    decoders
    |> Enum.map(&decode(&1, value, ops))
    |> ops.collect_ok.()
  end
end
