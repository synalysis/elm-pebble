defmodule Elmx.Runtime.Json.Decode.Runtime do
  @moduledoc false

  alias Elmx.Types

  @type decoder :: Types.json_decoder()
  @type decode_result :: Types.result_native()

  @spec normalize_input(Types.json_value() | String.t()) :: {:ok, Types.json_value()} | {:Err, String.t()}
  def normalize_input(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> {:ok, value}
    end
  end

  def normalize_input(value) when is_map(value), do: {:ok, value}
  def normalize_input(value) when is_list(value), do: {:ok, value}
  def normalize_input(value) when is_float(value), do: {:ok, value}
  def normalize_input(nil), do: {:ok, nil}
  def normalize_input(_), do: {:Err, "expected JSON value"}

  @spec apply_decoder(decoder(), Types.json_value()) :: decode_result()
  def apply_decoder({:json_decoder, :string}, value) when is_binary(value), do: {:Ok, value}

  def apply_decoder({:json_decoder, :string}, value) when is_map(value) do
    case Map.get(value, "value") || Map.get(value, :value) do
      text when is_binary(text) -> {:Ok, text}
      _ -> {:Err, "expected string"}
    end
  end

  def apply_decoder({:json_decoder, :int}, value) when is_integer(value), do: {:Ok, value}

  def apply_decoder({:json_decoder, :int}, value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> {:Ok, int}
      :error -> {:Err, "expected int"}
    end
  end

  def apply_decoder({:json_decoder, :float}, value) when is_number(value), do: {:Ok, value * 1.0}

  def apply_decoder({:json_decoder, :float}, value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> {:Ok, float}
      :error -> {:Err, "expected float"}
    end
  end

  def apply_decoder({:json_decoder, :bool}, value) when is_boolean(value), do: {:Ok, value}
  def apply_decoder({:json_decoder, :bool}, value) when value in [0, 1], do: {:Ok, value == 1}

  def apply_decoder({:json_decoder, :value}, value), do: {:Ok, value}

  def apply_decoder({:json_decoder, {:fail, message}}, _value), do: {:Err, message}

  def apply_decoder({:json_decoder, {:succeed, value}}, _value), do: {:Ok, value}

  def apply_decoder({:json_decoder, {:one_of, decoders}}, value) when is_list(decoders) do
    Enum.reduce_while(decoders, {:Err, "oneOf failed"}, fn decoder, _acc ->
      case apply_decoder(decoder, value) do
        {:Ok, _} = ok -> {:halt, ok}
        {:Err, _} -> {:cont, {:Err, "oneOf failed"}}
      end
    end)
  end

  def apply_decoder({:json_decoder, {:nullable, _inner}}, nil), do: {:Ok, :Nothing}

  def apply_decoder({:json_decoder, {:nullable, inner}}, value) do
    case apply_decoder(inner, value) do
      {:Ok, decoded} -> {:Ok, {:Just, decoded}}
      {:Err, _} = err -> err
    end
  end

  def apply_decoder({:json_decoder, {:maybe, inner}}, value) do
    case apply_decoder(inner, value) do
      {:Ok, decoded} -> {:Ok, {:Just, decoded}}
      {:Err, _} -> {:Ok, :Nothing}
    end
  end

  def apply_decoder({:json_decoder, {:null, default}}, nil), do: {:Ok, default}
  def apply_decoder({:json_decoder, {:null, _default}}, _), do: {:Err, "expected null"}

  def apply_decoder({:json_decoder, {:index, idx, inner}}, value) when is_list(value) do
    case Enum.at(value, idx) do
      nil -> {:Err, "index out of range"}
      elem -> apply_decoder(inner, elem)
    end
  end

  def apply_decoder({:json_decoder, {:index, _, _inner}}, _), do: {:Err, "expected array"}

  def apply_decoder({:json_decoder, {:dict, inner}}, value) when is_map(value) do
    decode_object_entries(value, inner, [])
    |> case do
      {:ok, pairs} -> {:Ok, Map.new(pairs)}
      {:error, message} -> {:Err, message}
    end
  end

  def apply_decoder({:json_decoder, {:key_value_pairs, inner}}, value) when is_map(value) do
    case decode_object_entries(value, inner, []) do
      {:ok, pairs} -> {:Ok, pairs}
      {:error, message} -> {:Err, message}
    end
  end

  def apply_decoder({:json_decoder, {:field, name, inner}}, value) when is_map(value) do
    case map_field(value, name) do
      {:ok, field_value} -> apply_decoder(inner, field_value)
      :error -> {:Err, "missing field #{name}"}
    end
  end

  def apply_decoder({:json_decoder, {:list, inner}}, values) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn item, {:ok, acc} ->
      case apply_decoder(inner, item) do
        {:Ok, decoded} -> {:cont, {:ok, [decoded | acc]}}
        {:Err, message} -> {:halt, {:error, message}}
      end
    end)
    |> case do
      {:ok, acc} -> {:Ok, Enum.reverse(acc)}
      {:error, message} -> {:Err, message}
    end
  end

  def apply_decoder({:json_decoder, {:list, _inner}}, _), do: {:Err, "expected array"}

  def apply_decoder({:json_decoder, {:map, fun, inner}}, value) when is_function(fun, 1) do
    case apply_decoder(inner, value) do
      {:Ok, decoded} -> {:Ok, fun.(decoded)}
      {:Err, _} = err -> err
    end
  end

  def apply_decoder({:json_decoder, {:map2, fun, d1, d2}}, value) when is_function(fun, 2) do
    with {:Ok, a} <- apply_decoder(d1, value),
         {:Ok, b} <- apply_decoder(d2, value) do
      {:Ok, fun.(a, b)}
    end
  end

  def apply_decoder({:json_decoder, {:map_n, fun, decoders}}, value) when is_list(decoders) do
    case decode_all(decoders, value) do
      {:ok, args} -> {:Ok, apply(fun, args)}
      {:error, message} -> {:Err, message}
    end
  end

  def apply_decoder({:json_decoder, {:lazy, thunk}}, value) when is_function(thunk, 0) do
    case thunk.() do
      {:json_decoder, _} = decoder -> apply_decoder(decoder, value)
      _ -> {:Err, "lazy decoder mismatch"}
    end
  end

  def apply_decoder({:json_decoder, {:and_then, fun, inner}}, value) when is_function(fun, 1) do
    with {:Ok, step} <- apply_decoder(inner, value),
         {:json_decoder, _} = next = fun.(step),
         {:Ok, decoded} <- apply_decoder(next, value) do
      {:Ok, decoded}
    end
  end

  def apply_decoder(_, _), do: {:Err, "decoder mismatch"}

  def decode_all(decoders, value) do
    Enum.reduce_while(decoders, {:ok, []}, fn decoder, {:ok, acc} ->
      case apply_decoder(decoder, value) do
        {:Ok, decoded} -> {:cont, {:ok, [decoded | acc]}}
        {:Err, message} -> {:halt, {:error, message}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      {:error, message} -> {:error, message}
    end
  end

  @dialyzer {:nowarn_function, decode_object_entries: 3}
  def decode_object_entries(value, inner, acc) when is_map(value) do
    Enum.reduce_while(value, {:ok, acc}, fn {key, field_value}, {:ok, pairs} ->
      key = normalize_object_key(key)

      case apply_decoder(inner, field_value) do
        {:Ok, decoded} -> {:cont, {:ok, [{key, decoded} | pairs]}}
        {:Err, message} -> {:halt, {:error, message}}
      end
    end)
    |> case do
      {:ok, pairs} -> {:ok, Enum.reverse(pairs)}
      {:error, message} -> {:error, message}
    end
  end

  def decode_object_entries(value, _inner, _acc) when not is_map(value),
    do: {:error, "expected object"}

  def normalize_object_key(key) when is_binary(key), do: key
  def normalize_object_key(key) when is_atom(key), do: Atom.to_string(key)

  def map_field(map, name) when is_map(map) and is_binary(name) do
    cond do
      Map.has_key?(map, name) -> {:ok, Map.get(map, name)}
      Map.has_key?(map, String.to_atom(name)) -> {:ok, Map.get(map, String.to_atom(name))}
      true -> :error
    end
  end
end
