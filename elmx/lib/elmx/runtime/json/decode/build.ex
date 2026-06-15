defmodule Elmx.Runtime.Json.Decode.Build do
  @moduledoc false

  alias Elmx.Types

  @type decoder :: Types.json_decoder()

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

  @spec null(Types.json_value()) :: decoder()
  def null(default), do: {:json_decoder, {:null, default}}

  @spec nullable(decoder()) :: decoder()
  def nullable(decoder), do: {:json_decoder, {:nullable, decoder}}

  @spec maybe(decoder()) :: decoder()
  def maybe(decoder), do: {:json_decoder, {:maybe, decoder}}

  @spec fail(String.t()) :: decoder()
  def fail(message) when is_binary(message), do: {:json_decoder, {:fail, message}}

  @spec and_then((Types.json_value() -> decoder()), decoder()) :: decoder()
  def and_then(fun, decoder) when is_function(fun, 1),
    do: {:json_decoder, {:and_then, fun, decoder}}

  @spec lazy((-> decoder())) :: decoder()
  def lazy(thunk) when is_function(thunk, 0), do: {:json_decoder, {:lazy, thunk}}

  @spec dict(decoder()) :: decoder()
  def dict(value_decoder), do: {:json_decoder, {:dict, value_decoder}}

  @spec key_value_pairs(decoder()) :: decoder()
  def key_value_pairs(value_decoder), do: {:json_decoder, {:key_value_pairs, value_decoder}}

  @spec map((Types.json_value() -> Types.elm_value()), decoder()) :: decoder()
  def map(fun, decoder) when is_function(fun, 1), do: {:json_decoder, {:map, fun, decoder}}

  @spec map_n(fun(), [decoder()]) :: decoder()
  def map_n(fun, decoders) when is_function(fun) and is_list(decoders),
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

  @spec succeed(Types.json_value()) :: decoder()
  def succeed(value), do: {:json_decoder, {:succeed, value}}

  @spec one_of([decoder()]) :: decoder()
  def one_of(decoders) when is_list(decoders), do: {:json_decoder, {:one_of, decoders}}

end
