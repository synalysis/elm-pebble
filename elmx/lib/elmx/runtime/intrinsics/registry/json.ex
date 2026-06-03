defmodule Elmx.Runtime.Intrinsics.Registry.Json do
  @moduledoc false

  alias Elmx.Runtime.Handler
  alias Elmx.Runtime.Json.Decode
  alias Elmx.Runtime.Json.Encode

  @type handler :: Handler.t()

  @spec handlers() :: %{String.t() => handler()}
  def handlers do
    Map.merge(decode_handlers(), encode_handlers())
  end

  @spec decode_handlers() :: %{String.t() => handler()}
  def decode_handlers do
    for suffix <- ~w(
         and_then array at bool_decoder dict error_to_string fail field float_decoder
         index int_decoder key_value_pairs lazy list map map2 map3 map4 map5 map6 map7
         maybe null nullable one_of string string_decoder succeed value value_decoder
       ),
       name = decode_name(suffix),
       into: %{} do
      {"elmc_json_decode_#{suffix}", {Decode, name}}
    end
  end

  @spec encode_handlers() :: %{String.t() => handler()}
  def encode_handlers do
    for {suffix, fun} <- [
          {"array", :list},
          {"set", :list},
          {"bool", :bool},
          {"dict", :dict},
          {"encode", :encode},
          {"float", :float},
          {"int", :int},
          {"list", :list},
          {"null", :null},
          {"object", :object},
          {"string", :string}
        ],
        into: %{} do
      {"elmc_json_encode_#{suffix}", {Encode, fun}}
    end
  end

  @spec decode_name(String.t()) :: atom()
  defp decode_name("string"), do: :decode_string
  defp decode_name("value"), do: :decode_value
  defp decode_name("bool_decoder"), do: :bool
  defp decode_name("int_decoder"), do: :int
  defp decode_name("float_decoder"), do: :float
  defp decode_name("string_decoder"), do: :string
  defp decode_name("value_decoder"), do: :value
  defp decode_name(suffix), do: String.to_atom(suffix)
end
