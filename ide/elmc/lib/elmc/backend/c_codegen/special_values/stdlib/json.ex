defmodule Elmc.Backend.CCodegen.SpecialValues.Stdlib.Json do
  @moduledoc false
  alias Elmc.Backend.CCodegen.Types, as: Types


  alias Elmc.Backend.CCodegen.SpecialValues.Helpers
  alias Elmc.Backend.CCodegen.Types

  @behaviour Elmc.Backend.CCodegen.SpecialValues.Handler

  @impl true
  @spec special_value_from_target(String.t(), Types.special_value_args()) ::
          Types.special_value_result()
  def special_value_from_target("Json.Decode.string", _args),
    do: %{op: :runtime_call, function: "elmc_json_decode_string_decoder", args: []}

  def special_value_from_target("Json.Decode.int", _args),
    do: %{op: :runtime_call, function: "elmc_json_decode_int_decoder", args: []}

  def special_value_from_target("Json.Decode.float", _args),
    do: %{op: :runtime_call, function: "elmc_json_decode_float_decoder", args: []}

  def special_value_from_target("Json.Decode.bool", _args),
    do: %{op: :runtime_call, function: "elmc_json_decode_bool_decoder", args: []}

  def special_value_from_target("Json.Decode.value", _args),
    do: %{op: :runtime_call, function: "elmc_json_decode_value_decoder", args: []}

  def special_value_from_target("Json.Encode.null", _args),
    do: %{op: :runtime_call, function: "elmc_json_encode_null", args: []}

  def special_value_from_target("Json.Decode.decodeValue", [decoder, value]),
    do: %{op: :runtime_call, function: "elmc_json_decode_value", args: [decoder, value]}

  def special_value_from_target("Json.Decode.decodeValue", []),
    do: Helpers.runtime_fn_lambda("elmc_json_decode_value", ["__decoder", "__value"])

  def special_value_from_target("Json.Decode.decodeString", [decoder, s]),
    do: %{op: :runtime_call, function: "elmc_json_decode_string", args: [decoder, s]}

  def special_value_from_target("Json.Decode.decodeString", []),
    do: Helpers.runtime_fn_lambda("elmc_json_decode_string", ["__decoder", "__s"])

  def special_value_from_target("Json.Decode.null", [default_val]),
    do: %{op: :runtime_call, function: "elmc_json_decode_null", args: [default_val]}

  def special_value_from_target("Json.Decode.null", []),
    do: Helpers.runtime_fn_lambda("elmc_json_decode_null", ["__default"])

  def special_value_from_target("Json.Decode.nullable", [decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_nullable", args: [decoder]}

  def special_value_from_target("Json.Decode.nullable", []),
    do: Helpers.runtime_fn_lambda("elmc_json_decode_nullable", ["__decoder"])

  def special_value_from_target("Json.Decode.list", [decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_list", args: [decoder]}

  def special_value_from_target("Json.Decode.list", []),
    do: Helpers.runtime_fn_lambda("elmc_json_decode_list", ["__decoder"])

  def special_value_from_target("Json.Decode.array", [decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_array", args: [decoder]}

  def special_value_from_target("Json.Decode.array", []),
    do: Helpers.runtime_fn_lambda("elmc_json_decode_array", ["__decoder"])

  def special_value_from_target("Json.Decode.field", [name, decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_field", args: [name, decoder]}

  def special_value_from_target("Json.Decode.field", []),
    do: Helpers.runtime_fn_lambda("elmc_json_decode_field", ["__name", "__decoder"])

  def special_value_from_target("Json.Decode.at", [path, decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_at", args: [path, decoder]}

  def special_value_from_target("Json.Decode.at", []),
    do: Helpers.runtime_fn_lambda("elmc_json_decode_at", ["__path", "__decoder"])

  def special_value_from_target("Json.Decode.index", [idx, decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_index", args: [idx, decoder]}

  def special_value_from_target("Json.Decode.index", []),
    do: Helpers.runtime_fn_lambda("elmc_json_decode_index", ["__idx", "__decoder"])

  def special_value_from_target("Json.Decode.map", [f, decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_map", args: [f, decoder]}

  def special_value_from_target("Json.Decode.map", []),
    do: Helpers.runtime_fn_lambda("elmc_json_decode_map", ["__f", "__decoder"])

  def special_value_from_target("Json.Decode.map2", [f, d1, d2]),
    do: %{op: :runtime_call, function: "elmc_json_decode_map2", args: [f, d1, d2]}

  def special_value_from_target("Json.Decode.map2", []),
    do: Helpers.runtime_fn_lambda("elmc_json_decode_map2", ["__f", "__d1", "__d2"])

  def special_value_from_target("Json.Decode.map3", [f, d1, d2, d3]),
    do: %{op: :runtime_call, function: "elmc_json_decode_map3", args: [f, d1, d2, d3]}

  def special_value_from_target("Json.Decode.map3", []),
    do: Helpers.runtime_fn_lambda("elmc_json_decode_map3", ["__f", "__d1", "__d2", "__d3"])

  def special_value_from_target("Json.Decode.map4", [f, d1, d2, d3, d4]),
    do: %{op: :runtime_call, function: "elmc_json_decode_map4", args: [f, d1, d2, d3, d4]}

  def special_value_from_target("Json.Decode.map4", []),
    do: Helpers.runtime_fn_lambda("elmc_json_decode_map4", ["__f", "__d1", "__d2", "__d3", "__d4"])

  def special_value_from_target("Json.Decode.map5", [f, d1, d2, d3, d4, d5]),
    do: %{op: :runtime_call, function: "elmc_json_decode_map5", args: [f, d1, d2, d3, d4, d5]}

  def special_value_from_target("Json.Decode.map5", []),
    do: Helpers.runtime_fn_lambda("elmc_json_decode_map5", ["__f", "__d1", "__d2", "__d3", "__d4", "__d5"])

  def special_value_from_target("Json.Decode.map6", [f, d1, d2, d3, d4, d5, d6]),
    do: %{op: :runtime_call, function: "elmc_json_decode_map6", args: [f, d1, d2, d3, d4, d5, d6]}

  def special_value_from_target("Json.Decode.map6", []),
    do: Helpers.runtime_fn_lambda("elmc_json_decode_map6", ["__f", "__d1", "__d2", "__d3", "__d4", "__d5", "__d6"])

  def special_value_from_target("Json.Decode.map7", [f, d1, d2, d3, d4, d5, d6, d7]),
    do: %{
      op: :runtime_call,
      function: "elmc_json_decode_map7",
      args: [f, d1, d2, d3, d4, d5, d6, d7]
    }

  def special_value_from_target("Json.Decode.map7", []),
    do:
      Helpers.runtime_fn_lambda("elmc_json_decode_map7", [
        "__f",
        "__d1",
        "__d2",
        "__d3",
        "__d4",
        "__d5",
        "__d6",
        "__d7"
      ])

  def special_value_from_target("Json.Decode.succeed", [value]),
    do: %{op: :runtime_call, function: "elmc_json_decode_succeed", args: [value]}

  def special_value_from_target("Json.Decode.succeed", []),
    do: Helpers.runtime_fn_lambda("elmc_json_decode_succeed", ["__value"])

  def special_value_from_target("Json.Decode.fail", [msg]),
    do: %{op: :runtime_call, function: "elmc_json_decode_fail", args: [msg]}

  def special_value_from_target("Json.Decode.fail", []),
    do: Helpers.runtime_fn_lambda("elmc_json_decode_fail", ["__msg"])

  def special_value_from_target("Json.Decode.andThen", [f, decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_and_then", args: [f, decoder]}

  def special_value_from_target("Json.Decode.andThen", []),
    do: Helpers.runtime_fn_lambda("elmc_json_decode_and_then", ["__f", "__decoder"])

  def special_value_from_target("Json.Decode.oneOf", [decoders]),
    do: %{op: :runtime_call, function: "elmc_json_decode_one_of", args: [decoders]}

  def special_value_from_target("Json.Decode.oneOf", []),
    do: Helpers.runtime_fn_lambda("elmc_json_decode_one_of", ["__decoders"])

  def special_value_from_target("Json.Decode.maybe", [decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_maybe", args: [decoder]}

  def special_value_from_target("Json.Decode.maybe", []),
    do: Helpers.runtime_fn_lambda("elmc_json_decode_maybe", ["__decoder"])

  def special_value_from_target("Json.Decode.lazy", [thunk]),
    do: %{op: :runtime_call, function: "elmc_json_decode_lazy", args: [thunk]}

  def special_value_from_target("Json.Decode.lazy", []),
    do: Helpers.runtime_fn_lambda("elmc_json_decode_lazy", ["__thunk"])

  def special_value_from_target("Json.Decode.errorToString", [err]),
    do: %{op: :runtime_call, function: "elmc_json_decode_error_to_string", args: [err]}

  def special_value_from_target("Json.Decode.errorToString", []),
    do: %{
      op: :lambda,
      args: ["__err"],
      body: %{
        op: :runtime_call,
        function: "elmc_json_decode_error_to_string",
        args: [%{op: :var, name: "__err"}]
      }
    }

  def special_value_from_target("Json.Decode.keyValuePairs", [decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_key_value_pairs", args: [decoder]}

  def special_value_from_target("Json.Decode.keyValuePairs", []),
    do: Helpers.runtime_fn_lambda("elmc_json_decode_key_value_pairs", ["__decoder"])

  def special_value_from_target("Json.Decode.dict", [decoder]),
    do: %{op: :runtime_call, function: "elmc_json_decode_dict", args: [decoder]}

  def special_value_from_target("Json.Decode.dict", []),
    do: Helpers.runtime_fn_lambda("elmc_json_decode_dict", ["__decoder"])

  # --- elm/json: Json.Encode ---
  def special_value_from_target("Json.Encode.string", [s]),
    do: %{op: :runtime_call, function: "elmc_json_encode_string", args: [s]}

  def special_value_from_target("Json.Encode.string", []),
    do: Helpers.runtime_fn_lambda("elmc_json_encode_string", ["__s"])

  def special_value_from_target("Json.Encode.int", [n]),
    do: %{op: :runtime_call, function: "elmc_json_encode_int", args: [n]}

  def special_value_from_target("Json.Encode.int", []),
    do: Helpers.runtime_fn_lambda("elmc_json_encode_int", ["__n"])

  def special_value_from_target("Json.Encode.float", [f]),
    do: %{op: :runtime_call, function: "elmc_json_encode_float", args: [f]}

  def special_value_from_target("Json.Encode.float", []),
    do: Helpers.runtime_fn_lambda("elmc_json_encode_float", ["__f"])

  def special_value_from_target("Json.Encode.bool", [b]),
    do: %{op: :runtime_call, function: "elmc_json_encode_bool", args: [b]}

  def special_value_from_target("Json.Encode.bool", []),
    do: Helpers.runtime_fn_lambda("elmc_json_encode_bool", ["__b"])

  def special_value_from_target("Json.Encode.list", [f, items]),
    do: %{op: :runtime_call, function: "elmc_json_encode_list", args: [f, items]}

  def special_value_from_target("Json.Encode.list", [_f]),
    do: Helpers.runtime_fn_lambda("elmc_json_encode_list", ["__f", "__items"])

  def special_value_from_target("Json.Encode.array", [f, items]),
    do: %{op: :runtime_call, function: "elmc_json_encode_array", args: [f, items]}

  def special_value_from_target("Json.Encode.array", [_f]),
    do: Helpers.runtime_fn_lambda("elmc_json_encode_array", ["__f", "__items"])

  def special_value_from_target("Json.Encode.set", [f, items]),
    do: %{op: :runtime_call, function: "elmc_json_encode_set", args: [f, items]}

  def special_value_from_target("Json.Encode.encode", [indent, value]),
    do: %{op: :runtime_call, function: "elmc_json_encode_encode", args: [indent, value]}

  def special_value_from_target("Json.Encode.encode", []),
    do: Helpers.runtime_fn_lambda("elmc_json_encode_encode", ["__indent", "__value"])

  def special_value_from_target("Json.Encode.object", [pairs]),
    do: %{op: :runtime_call, function: "elmc_json_encode_object", args: [pairs]}

  def special_value_from_target("Json.Encode.object", []),
    do: Helpers.runtime_fn_lambda("elmc_json_encode_object", ["__pairs"])

  def special_value_from_target("Json.Encode.dict", [key_fn, val_fn, dict]),
    do: %{op: :runtime_call, function: "elmc_json_encode_dict", args: [key_fn, val_fn, dict]}

  def special_value_from_target("Json.Encode.dict", []),
    do: Helpers.runtime_fn_lambda("elmc_json_encode_dict", ["__key_fn", "__val_fn", "__dict"])

  def special_value_from_target("Elm.Kernel.Json.wrap", []),
    do: %{op: :lambda, args: ["__v"], body: %{op: :var, name: "__v"}}

  def special_value_from_target("Elm.Kernel.Json.wrap", [value]), do: value

  def special_value_from_target("Elm.Kernel.Json.emptyObject", _args),
    do: %{op: :list_literal, items: []}

  def special_value_from_target("Elm.Kernel.Json.emptyArray", _args),
    do: %{op: :list_literal, items: []}

  def special_value_from_target("Elm.Kernel.Json.addField", [key, value, obj]),
    do: %{op: :runtime_call, function: "elmc_json_encode_add_field", args: [key, value, obj]}

  def special_value_from_target("Elm.Kernel.Json.addField", [key, value]),
    do: %{
      op: :lambda,
      args: ["__obj"],
      body: %{
        op: :runtime_call,
        function: "elmc_json_encode_add_field",
        args: [key, value, %{op: :var, name: "__obj"}]
      }
    }

  def special_value_from_target("Elm.Kernel.Json.addField", [key]),
    do: %{
      op: :lambda,
      args: ["__value"],
      body: %{
        op: :lambda,
        args: ["__obj"],
        body: %{
          op: :runtime_call,
          function: "elmc_json_encode_add_field",
          args: [key, %{op: :var, name: "__value"}, %{op: :var, name: "__obj"}]
        }
      }
    }

  def special_value_from_target("Elm.Kernel.Json.addEntry", [func, value, arr]),
    do: %{op: :runtime_call, function: "elmc_json_encode_add_entry", args: [func, value, arr]}

  def special_value_from_target("Elm.Kernel.Json.addEntry", [func, value]),
    do: %{
      op: :lambda,
      args: ["__arr"],
      body: %{
        op: :runtime_call,
        function: "elmc_json_encode_add_entry",
        args: [func, value, %{op: :var, name: "__arr"}]
      }
    }

  def special_value_from_target("Elm.Kernel.Json.addEntry", [func]),
    do: %{
      op: :lambda,
      args: ["__value"],
      body: %{
        op: :lambda,
        args: ["__arr"],
        body: %{
          op: :runtime_call,
          function: "elmc_json_encode_add_entry",
          args: [func, %{op: :var, name: "__value"}, %{op: :var, name: "__arr"}]
        }
      }
    }

  def special_value_from_target(_target, _args), do: nil
end
