defmodule Elmx.Runtime.Json.Decode do
  @moduledoc """
  Minimal composable `Json.Decode` runtime for companion phone templates.

  Decoders are opaque `{:json_decoder, spec}` terms composed at compile time and
  interpreted by `decode_value/2` against plain maps or JSON strings.
  """

  @type decoder :: {:json_decoder, term()}

  @spec string() :: decoder()
  def string, do: {:json_decoder, :string}

  @spec int() :: decoder()
  def int, do: {:json_decoder, :int}

  @spec float() :: decoder()
  def float, do: {:json_decoder, :float}

  @spec bool() :: decoder()
  def bool, do: {:json_decoder, :bool}

  @spec value() :: decoder()
  def value, do: {:json_decoder, :value}

  @spec field(String.t(), decoder()) :: decoder()
  def field(name, decoder) when is_binary(name), do: {:json_decoder, {:field, name, decoder}}

  @spec optional_field(String.t(), decoder()) :: decoder()
  def optional_field(name, decoder) when is_binary(name),
    do: {:json_decoder, {:optional_field, name, decoder}}

  @spec list(decoder()) :: decoder()
  def list(decoder), do: {:json_decoder, {:list, decoder}}

  @spec array(decoder()) :: decoder()
  def array(decoder), do: {:json_decoder, {:list, decoder}}

  @spec index(integer(), decoder()) :: decoder()
  def index(idx, decoder) when is_integer(idx), do: {:json_decoder, {:index, idx, decoder}}

  @spec at(list(), decoder()) :: decoder()
  def at(path, decoder) when is_list(path) do
    Enum.reduce(Enum.reverse(path), decoder, &field/2)
  end

  @spec null(term()) :: decoder()
  def null(default), do: {:json_decoder, {:null, default}}

  @spec nullable(decoder()) :: decoder()
  def nullable(decoder), do: {:json_decoder, {:nullable, decoder}}

  @spec maybe(decoder()) :: decoder()
  def maybe(decoder), do: {:json_decoder, {:maybe, decoder}}

  @spec fail(String.t()) :: decoder()
  def fail(message) when is_binary(message), do: {:json_decoder, {:fail, message}}

  @spec and_then((term() -> decoder()), decoder()) :: decoder()
  def and_then(fun, decoder) when is_function(fun, 1),
    do: {:json_decoder, {:and_then, fun, decoder}}

  @spec lazy((-> decoder())) :: decoder()
  def lazy(thunk) when is_function(thunk, 0), do: {:json_decoder, {:lazy, thunk}}

  @spec dict(decoder()) :: decoder()
  def dict(value_decoder), do: {:json_decoder, {:dict, value_decoder}}

  @spec key_value_pairs(decoder()) :: decoder()
  def key_value_pairs(value_decoder), do: {:json_decoder, {:key_value_pairs, value_decoder}}

  @spec map((term() -> term()), decoder()) :: decoder()
  def map(fun, decoder) when is_function(fun, 1), do: {:json_decoder, {:map, fun, decoder}}

  @spec map_n(fun(), [decoder()]) :: decoder()
  defp map_n(fun, decoders) when is_function(fun) and is_list(decoders),
    do: {:json_decoder, {:map_n, fun, decoders}}

  @spec map2(fun(), decoder(), decoder()) :: decoder()
  def map2(fun, d1, d2) when is_function(fun, 2), do: map_n(fun, [d1, d2])

  @spec map3(fun(), decoder(), decoder(), decoder()) :: decoder()
  def map3(fun, d1, d2, d3) when is_function(fun, 3), do: map_n(fun, [d1, d2, d3])

  @spec map4(fun(), decoder(), decoder(), decoder(), decoder()) :: decoder()
  def map4(fun, d1, d2, d3, d4) when is_function(fun, 4), do: map_n(fun, [d1, d2, d3, d4])

  @spec map5(fun(), decoder(), decoder(), decoder(), decoder(), decoder()) :: decoder()
  def map5(fun, d1, d2, d3, d4, d5) when is_function(fun, 5), do: map_n(fun, [d1, d2, d3, d4, d5])

  @spec map6(fun(), decoder(), decoder(), decoder(), decoder(), decoder(), decoder()) ::
          decoder()
  def map6(fun, d1, d2, d3, d4, d5, d6) when is_function(fun, 6),
    do: map_n(fun, [d1, d2, d3, d4, d5, d6])

  @spec map7(fun(), decoder(), decoder(), decoder(), decoder(), decoder(), decoder(), decoder()) ::
          decoder()
  def map7(fun, d1, d2, d3, d4, d5, d6, d7) when is_function(fun, 7),
    do: map_n(fun, [d1, d2, d3, d4, d5, d6, d7])

  @spec succeed(term()) :: decoder()
  def succeed(value), do: {:json_decoder, {:succeed, value}}

  @spec one_of(list()) :: decoder()
  def one_of(decoders) when is_list(decoders), do: {:json_decoder, {:one_of, decoders}}

  @spec decode_string(decoder(), String.t()) :: {:Ok, term()} | {:Err, String.t()}
  def decode_string(decoder, json) when is_binary(json), do: decode_value(decoder, json)

  @spec decode_value(decoder(), term()) :: {:Ok, term()} | {:Err, String.t()}
  def decode_value(decoder, value) do
    with {:ok, normalized} <- normalize_input(value) do
      apply_decoder(decoder, normalized)
    end
  end

  @spec error_to_string(term()) :: String.t()
  def error_to_string(message) when is_binary(message), do: message
  def error_to_string(other), do: inspect(other)

  defp normalize_input(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> {:ok, value}
    end
  end

  defp normalize_input(value) when is_map(value), do: {:ok, value}
  defp normalize_input(value) when is_list(value), do: {:ok, value}
  defp normalize_input(nil), do: {:ok, nil}
  defp normalize_input(_), do: {:Err, "expected JSON value"}

  defp apply_decoder({:json_decoder, :string}, value) when is_binary(value), do: {:Ok, value}

  defp apply_decoder({:json_decoder, :string}, value) when is_map(value) do
    case Map.get(value, "value") || Map.get(value, :value) do
      text when is_binary(text) -> {:Ok, text}
      _ -> {:Err, "expected string"}
    end
  end

  defp apply_decoder({:json_decoder, :int}, value) when is_integer(value), do: {:Ok, value}

  defp apply_decoder({:json_decoder, :int}, value) when is_float(value),
    do: {:Ok, trunc(value)}

  defp apply_decoder({:json_decoder, :int}, value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> {:Ok, int}
      :error -> {:Err, "expected int"}
    end
  end

  defp apply_decoder({:json_decoder, :float}, value) when is_number(value), do: {:Ok, value * 1.0}

  defp apply_decoder({:json_decoder, :float}, value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> {:Ok, float}
      :error -> {:Err, "expected float"}
    end
  end

  defp apply_decoder({:json_decoder, :bool}, value) when is_boolean(value), do: {:Ok, value}
  defp apply_decoder({:json_decoder, :bool}, value) when value in [0, 1], do: {:Ok, value == 1}

  defp apply_decoder({:json_decoder, :value}, value), do: {:Ok, value}

  defp apply_decoder({:json_decoder, {:fail, message}}, _value), do: {:Err, message}

  defp apply_decoder({:json_decoder, {:succeed, value}}, _value), do: {:Ok, value}

  defp apply_decoder({:json_decoder, {:one_of, decoders}}, value) when is_list(decoders) do
    Enum.reduce_while(decoders, {:Err, "oneOf failed"}, fn decoder, _acc ->
      case apply_decoder(decoder, value) do
        {:Ok, _} = ok -> {:halt, ok}
        {:Err, _} -> {:cont, {:Err, "oneOf failed"}}
      end
    end)
  end

  defp apply_decoder({:json_decoder, {:nullable, _inner}}, nil), do: {:Ok, :Nothing}

  defp apply_decoder({:json_decoder, {:nullable, inner}}, value) do
    case apply_decoder(inner, value) do
      {:Ok, decoded} -> {:Ok, {:Just, decoded}}
      {:Err, _} = err -> err
    end
  end

  defp apply_decoder({:json_decoder, {:maybe, inner}}, value) do
    case apply_decoder(inner, value) do
      {:Ok, decoded} -> {:Ok, {:Just, decoded}}
      {:Err, _} -> {:Ok, :Nothing}
    end
  end

  defp apply_decoder({:json_decoder, {:null, default}}, nil), do: {:Ok, default}
  defp apply_decoder({:json_decoder, {:null, _default}}, _), do: {:Err, "expected null"}

  defp apply_decoder({:json_decoder, {:index, idx, inner}}, value) when is_list(value) do
    case Enum.at(value, idx) do
      nil -> {:Err, "index out of range"}
      elem -> apply_decoder(inner, elem)
    end
  end

  defp apply_decoder({:json_decoder, {:index, _, _inner}}, _), do: {:Err, "expected array"}

  defp apply_decoder({:json_decoder, {:dict, inner}}, value) when is_map(value) do
    decode_object_entries(value, inner, [])
    |> case do
      {:ok, pairs} -> {:Ok, Map.new(pairs)}
      {:error, message} -> {:Err, message}
    end
  end

  defp apply_decoder({:json_decoder, {:key_value_pairs, inner}}, value) when is_map(value) do
    case decode_object_entries(value, inner, []) do
      {:ok, pairs} -> {:Ok, pairs}
      {:error, message} -> {:Err, message}
    end
  end

  defp apply_decoder({:json_decoder, {:field, name, inner}}, value) when is_map(value) do
    case map_field(value, name) do
      {:ok, field_value} -> apply_decoder(inner, field_value)
      :error -> {:Err, "missing field #{name}"}
    end
  end

  defp apply_decoder({:json_decoder, {:optional_field, name, inner}}, value) when is_map(value) do
    case map_field(value, name) do
      {:ok, field_value} ->
        case apply_decoder(inner, field_value) do
          {:Ok, decoded} -> {:Ok, {:Just, decoded}}
          {:Err, _} = err -> err
        end

      :error ->
        {:Ok, :Nothing}
    end
  end

  defp apply_decoder({:json_decoder, {:list, inner}}, values) when is_list(values) do
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

  defp apply_decoder({:json_decoder, {:list, _inner}}, _), do: {:Err, "expected array"}

  defp apply_decoder({:json_decoder, {:map, fun, inner}}, value) when is_function(fun, 1) do
    case apply_decoder(inner, value) do
      {:Ok, decoded} -> {:Ok, fun.(decoded)}
      {:Err, _} = err -> err
    end
  end

  defp apply_decoder({:json_decoder, {:map2, fun, d1, d2}}, value) when is_function(fun, 2) do
    with {:Ok, a} <- apply_decoder(d1, value),
         {:Ok, b} <- apply_decoder(d2, value) do
      {:Ok, fun.(a, b)}
    end
  end

  defp apply_decoder({:json_decoder, {:map_n, fun, decoders}}, value) when is_list(decoders) do
    case decode_all(decoders, value) do
      {:ok, args} -> {:Ok, apply(fun, args)}
      {:error, message} -> {:Err, message}
    end
  end

  defp apply_decoder({:json_decoder, {:lazy, thunk}}, value) when is_function(thunk, 0) do
    case thunk.() do
      {:json_decoder, _} = decoder -> apply_decoder(decoder, value)
      _ -> {:Err, "lazy decoder mismatch"}
    end
  end

  defp apply_decoder({:json_decoder, {:and_then, fun, inner}}, value) when is_function(fun, 1) do
    with {:Ok, step} <- apply_decoder(inner, value),
         {:json_decoder, _} = next = fun.(step),
         {:Ok, decoded} <- apply_decoder(next, value) do
      {:Ok, decoded}
    end
  end

  defp apply_decoder(_, _), do: {:Err, "decoder mismatch"}

  defp decode_all(decoders, value) do
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
  defp decode_object_entries(value, inner, acc) when is_map(value) do
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

  defp decode_object_entries(value, _inner, _acc) when not is_map(value),
    do: {:error, "expected object"}

  defp normalize_object_key(key) when is_binary(key), do: key
  defp normalize_object_key(key) when is_atom(key), do: Atom.to_string(key)

  defp map_field(map, name) when is_map(map) and is_binary(name) do
    cond do
      Map.has_key?(map, name) -> {:ok, Map.get(map, name)}
      Map.has_key?(map, String.to_atom(name)) -> {:ok, Map.get(map, String.to_atom(name))}
      true -> :error
    end
  end
end
