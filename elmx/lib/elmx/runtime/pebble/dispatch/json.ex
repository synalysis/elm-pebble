defmodule Elmx.Runtime.Pebble.Dispatch.Json do
  @moduledoc false

  alias Elmx.Runtime.Json.Encode
  alias Elmx.Types

  @spec encode_object(Types.registry_args()) :: %{String.t() => Types.json_value()}
  def encode_object(args), do: Encode.object(List.first(args) || [])

  @spec encode_string(Types.registry_args()) :: String.t()
  def encode_string(args), do: Encode.string(List.first(args))

  @spec encode_int(Types.registry_args()) :: number()
  def encode_int(args), do: Encode.int(List.first(args))

  @spec encode_bool(Types.registry_args()) :: boolean()
  def encode_bool(args), do: Encode.bool(List.first(args))

  @spec encode_null(Types.registry_args()) :: nil
  def encode_null(_), do: Encode.null()

  @spec encode_list(Types.registry_args()) :: [Types.json_value()]
  def encode_list([encoder, items]) when is_function(encoder, 1), do: Encode.list(encoder, items)
  def encode_list([_encoder, items]) when is_list(items), do: items
  def encode_list([items]) when is_list(items), do: items
  def encode_list(_), do: []

  @spec encode_float(Types.registry_args()) :: float()
  def encode_float([value]), do: Encode.float(value)
  def encode_float(_), do: 0.0

  @spec encode_encode(Types.registry_args()) :: String.t()
  def encode_encode([indent, value]) when is_integer(indent), do: Encode.encode(indent, value)
  def encode_encode(_), do: "null"

  @spec encode_dict(Types.registry_args()) :: %{String.t() => Types.json_value()}
  def encode_dict([key_fn, val_fn, dict]) when is_function(key_fn, 1) and is_function(val_fn, 1) do
    dict
    |> Map.new(fn {k, v} -> {key_fn.(k), val_fn.(v)} end)
  end

  def encode_dict([_key_fn, _val_fn, dict]) when is_map(dict), do: dict
  def encode_dict(_), do: %{}
end
