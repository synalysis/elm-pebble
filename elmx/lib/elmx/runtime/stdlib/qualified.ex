defmodule Elmx.Runtime.Stdlib.Qualified do
  @moduledoc """
  String codegen for qualified Elm stdlib calls (`List.map`, `Dict.*`, `Json.Decode.*`, …).

  `call/2` lowers a target and pre-rendered argument string to runtime Elixir source.
  `handles?/1` probes `call/2` and collection prefixes for emit-time discovery.
  `explicit_call_targets/0` lists every `def call("…")` clause for contract tests.

  IR emit delegates here via `Stdlib.qualified_call/2` after specialized emit rules;
  see `Elmx.Backend.ElixirCodegen.Emit.Qualified` (split into `Emit.Qualified.*` domain modules).
  Shared helpers live in `Stdlib.Qualified.Helpers`; codegen fragments in `Stdlib.QualifiedCodegen`.
  """

  alias Elmx.Runtime.CodegenRefs
  alias Elmx.Runtime.Stdlib.Qualified.Helpers
  alias Elmx.Runtime.Stdlib.QualifiedCodegen
  alias Elmx.Types

  @collection_op_prefixes ~w(Dict. Set. Array.)

  @doc """
  Returns whether `target` is handled by this module (including `Dict.*`, `Set.*`, `Array.*` ops).
  """
  @spec explicit_call_targets() :: [String.t()]
  def explicit_call_targets do
    path = Path.join(__DIR__, "qualified.ex")

    path
    |> File.read!()
    |> then(&Regex.scan(~r/^\s*def call\("([^"]+)",/m, &1))
    |> Enum.map(fn [_, target] -> target end)
  end

  @spec handles?(String.t()) :: boolean()
  def handles?(target) when is_binary(target) do
    Enum.any?(@collection_op_prefixes, &String.starts_with?(target, &1)) or
      Enum.any?(qualified_arg_probes(), &match?({:ok, _}, call(target, &1)))
  end

  defp qualified_arg_probes do
    [
      "a, b",
      "a, b, c",
      "a, b, c, d",
      "a, b, c, d, e",
      "a, b, c, d, e, f",
      "a, b, c, d, e, f, g",
      "a, b, c, d, e, f, g, h",
      "0, 1, s",
      "decoder, value",
      "decoders",
      "step, dec",
      "a",
      ""
    ]
  end

  @spec call(String.t(), Types.qualified_arg_code()) :: Types.qualified_call_result()
  def call("List.filter", arg_code), do: Helpers.list_core_hof("filter", arg_code)
  def call("List.map", arg_code), do: Helpers.list_core_hof("map", arg_code)
  def call("List.filterMap", arg_code), do: Helpers.list_core_hof("filter_map", arg_code)
  def call("List.concatMap", arg_code), do: Helpers.list_core_hof("concat_map", arg_code)
  def call("List.sortBy", arg_code), do: Helpers.list_core_hof("sort_by", arg_code)
  def call("List.sortWith", arg_code), do: Helpers.list_core_hof("sort_with", arg_code)
  def call("List.sum", arg_code), do: Helpers.core_unary("list_sum", arg_code)
  def call("List.product", arg_code), do: Helpers.core_unary("list_product", arg_code)
  def call("List.maximum", arg_code), do: Helpers.core_unary("list_maximum", arg_code)
  def call("List.minimum", arg_code), do: Helpers.core_unary("list_minimum", arg_code)
  def call("List.any", arg_code), do: Helpers.list_core_hof("any", arg_code)
  def call("List.all", arg_code), do: Helpers.list_core_hof("all", arg_code)
  def call("List.foldl", arg_code), do: Helpers.list_core_fold("foldl", arg_code)
  def call("List.foldr", arg_code), do: Helpers.list_core_fold("foldr", arg_code)
  def call("List.repeat", arg_code), do: Helpers.list_repeat(arg_code)
  def call("List.member", arg_code), do: Helpers.list_member(arg_code)
  def call("List.sort", arg_code), do: Helpers.core_unary("sort", arg_code)
  def call("List.head", arg_code), do: Helpers.core_unary("list_head", arg_code)

  def call("List.indexedMap", arg_code) do
    case Helpers.split_args(arg_code) do
      [fun, list] -> QualifiedCodegen.list_hof("indexed_map", fun, list)
      [fun] -> QualifiedCodegen.list_hof("indexed_map", fun, nil)
      _ -> :error
    end
  end
  def call("List.range", arg_code) do
    case Helpers.split_args(arg_code) do
      [first, last] -> {:ok, "Elmx.Runtime.Core.List.list_range(#{first}, #{last})"}
      _ -> :error
    end
  end
  def call("String.fromInt", arg_code), do: Helpers.unary("Integer.to_string", arg_code)
  def call("String.append", arg_code), do: Helpers.runtime_binary(Elmx.Runtime.Core, "append", arg_code)
  def call("String.replace", arg_code), do: Helpers.string_replace(arg_code)
  def call("String.split", arg_code), do: Helpers.string_split(arg_code)
  def call("String.join", arg_code), do: Helpers.string_join(arg_code)
  def call("String.contains", arg_code), do: Helpers.string_binary("contains", arg_code)
  def call("String.startsWith", arg_code), do: Helpers.string_binary("starts_with", arg_code)
  def call("String.endsWith", arg_code), do: Helpers.string_binary("ends_with", arg_code)
  def call("String.repeat", arg_code), do: Helpers.string_repeat(arg_code)
  def call("Basics.compare", arg_code), do: Helpers.runtime_binary(Elmx.Runtime.Core, "basics_compare", arg_code)
  def call("Basics.clamp", arg_code), do: Helpers.runtime_ternary(Elmx.Runtime.Core, "basics_clamp", arg_code)
  def call("String.length", arg_code), do: Helpers.string_unary("length_val", arg_code)
  def call("String.reverse", arg_code), do: Helpers.string_unary("reverse", arg_code)
  def call("String.words", arg_code), do: Helpers.string_unary("words", arg_code)
  def call("String.lines", arg_code), do: Helpers.string_unary("lines", arg_code)
  def call("String.trimLeft", arg_code), do: Helpers.string_unary("trim_left", arg_code)
  def call("String.trimRight", arg_code), do: Helpers.string_unary("trim_right", arg_code)
  def call("String.toInt", arg_code), do: Helpers.string_to_int(arg_code)
  def call("String.toFloat", arg_code), do: Helpers.string_to_float(arg_code)
  def call("String.fromFloat", arg_code), do: Helpers.string_unary("from_float", arg_code)
  def call("String.slice", arg_code), do: Helpers.string_slice(arg_code)
  def call("String.pad", arg_code), do: Helpers.string_pad("pad", arg_code)
  def call("String.padLeft", arg_code), do: Helpers.string_pad("pad_left", arg_code)
  def call("String.padRight", arg_code), do: Helpers.string_pad("pad_right", arg_code)
  def call("String.cons", arg_code), do: Helpers.string_binary("cons", arg_code)
  def call("String.uncons", arg_code), do: Helpers.string_unary("uncons", arg_code)
  def call("String.toList", arg_code), do: Helpers.string_unary("to_list", arg_code)
  def call("String.fromList", arg_code), do: Helpers.string_unary("from_list", arg_code)
  def call("String.fromChar", arg_code), do: Helpers.string_unary("from_char", arg_code)
  def call("String.map", arg_code), do: Helpers.strings_container(arg_code, "map", 2)
  def call("String.filter", arg_code), do: Helpers.strings_container(arg_code, "filter", 2)
  def call("String.all", arg_code), do: Helpers.strings_container(arg_code, "all", 2)
  def call("String.any", arg_code), do: Helpers.strings_container(arg_code, "any", 2)
  def call("String.foldl", arg_code), do: Helpers.strings_container(arg_code, "foldl", 3)
  def call("String.foldr", arg_code), do: Helpers.strings_container(arg_code, "foldr", 3)
  def call("String.indexes", arg_code), do: Helpers.strings_container(arg_code, "indexes", 2)
  def call("String.indices", arg_code), do: Helpers.strings_container(arg_code, "indexes", 2)
  def call("Basics.not", arg_code), do: Helpers.unary("not", arg_code)
  def call("Basics.abs", arg_code), do: Helpers.unary("abs", arg_code)
  def call("Basics.min", arg_code), do: Helpers.binary_fn("min", arg_code)
  def call("Basics.max", arg_code), do: Helpers.binary_fn("max", arg_code)
  def call("Basics.modBy", arg_code), do: Helpers.mod_by(arg_code)
  def call("Basics.remainderBy", arg_code), do: Helpers.remainder_by(arg_code)
  def call("Maybe.withDefault", arg_code), do: Helpers.maybe_with_default(arg_code)
  def call("Maybe.map", arg_code), do: Helpers.maybe_map(arg_code)
  def call("Maybe.andThen", arg_code), do: Helpers.maybe_and_then(arg_code)
  def call("Result.mapError", arg_code), do: Helpers.result_map_error(arg_code)
  def call("Result.andThen", arg_code), do: Helpers.result_and_then(arg_code)
  def call("Basics.negate", arg_code), do: Helpers.basics_negate(arg_code)

  @math_unary_calls [
    {"Basics.sin", "sin"},
    {"Basics.cos", "cos"},
    {"Basics.tan", "tan"},
    {"Basics.sqrt", "sqrt"},
    {"Basics.asin", "asin"},
    {"Basics.acos", "acos"},
    {"Basics.atan", "atan"},
    {"Basics.degrees", "degrees"},
    {"Basics.radians", "radians"},
    {"Basics.turns", "turns"},
    {"Basics.isInfinite", "is_infinite"},
    {"Basics.isNaN", "is_nan"},
    {"Basics.toPolar", "to_polar"}
  ]

  for {target, fun} <- @math_unary_calls do
    def call(unquote(target), arg_code),
      do: Helpers.runtime_unary(Elmx.Runtime.Core.Math, unquote(fun), arg_code)
  end

  @math_binary_calls [
    {"Basics.atan2", "atan2"},
    {"Basics.pow", "pow"},
    {"Basics.logBase", "log_base"},
    {"Basics.xor", "xor"}
  ]

  for {target, fun} <- @math_binary_calls do
    def call(unquote(target), arg_code),
      do: Helpers.runtime_binary(Elmx.Runtime.Core.Math, unquote(fun), arg_code)
  end

  @char_unary_calls [
    {"Char.toUpper", "to_upper"},
    {"Char.toLower", "to_lower"},
    {"Char.toLocaleUpper", "to_upper"},
    {"Char.toLocaleLower", "to_lower"}
  ]

  for {target, fun} <- @char_unary_calls do
    def call(unquote(target), arg_code),
      do: Helpers.runtime_unary(Elmx.Runtime.Core.Chars, unquote(fun), arg_code)
  end

  @char_predicate_calls [
    {"Char.isDigit", "is_digit"},
    {"Char.isHexDigit", "is_hex_digit"},
    {"Char.isOctDigit", "is_oct_digit"},
    {"Char.isLower", "is_lower"},
    {"Char.isUpper", "is_upper"},
    {"Char.isAlpha", "is_alpha"},
    {"Char.isAlphaNum", "is_alpha_num"}
  ]

  for {target, fun} <- @char_predicate_calls do
    def call(unquote(target), arg_code),
      do: Helpers.runtime_unary(Elmx.Runtime.Core.Chars, unquote(fun), arg_code)
  end

  def call("Json.Encode.string", arg_code), do: Helpers.wrapped_runtime_unary(Elmx.Runtime.Json.Encode, "string", arg_code)
  def call("Json.Encode.int", arg_code), do: Helpers.wrapped_runtime_unary(Elmx.Runtime.Json.Encode, "int", arg_code)
  def call("Json.Encode.float", arg_code), do: Helpers.wrapped_runtime_unary(Elmx.Runtime.Json.Encode, "float", arg_code)
  def call("Json.Encode.bool", arg_code), do: Helpers.wrapped_runtime_unary(Elmx.Runtime.Json.Encode, "bool", arg_code)
  def call("Json.Encode.null", _arg_code), do: QualifiedCodegen.module_call(Elmx.Runtime.Json.Encode, "null", [])
  def call("Json.Encode.encode", arg_code), do: Helpers.runtime_binary(Elmx.Runtime.Json.Encode, "encode", arg_code)
  def call("Dict.get", arg_code), do: Helpers.dict_get(arg_code)
  def call("Dict.insert", arg_code), do: Helpers.dict_insert(arg_code)
  def call("Dict.remove", arg_code), do: Helpers.dict_remove(arg_code)
  def call("Dict.member", arg_code), do: Helpers.dict_member(arg_code)

  def call("Set.insert", arg_code), do: Helpers.set_insert(arg_code)
  def call("Set.remove", arg_code), do: Helpers.set_remove(arg_code)
  def call("Set.member", arg_code), do: Helpers.set_member(arg_code)

  def call("Dict." <> rest, arg_code),
    do: QualifiedCodegen.collection_call(CodegenRefs.core_collections(), "dict", rest, arg_code)

  def call("Set." <> rest, arg_code),
    do: QualifiedCodegen.collection_call(CodegenRefs.core_collections(), "set", rest, arg_code)

  def call("Array." <> rest, arg_code),
    do: QualifiedCodegen.collection_call(CodegenRefs.core_collections(), "array", rest, arg_code)

  def call("Task.succeed", arg_code), do: Helpers.runtime_unary(Elmx.Runtime.Core.Task, "succeed", arg_code)
  def call("Task.fail", arg_code), do: Helpers.runtime_unary(Elmx.Runtime.Core.Task, "fail", arg_code)
  def call("Task.map", arg_code), do: Helpers.runtime_binary(Elmx.Runtime.Core.Task, "map", arg_code)
  def call("Task.andThen", arg_code), do: Helpers.runtime_binary(Elmx.Runtime.Core.Task, "and_then", arg_code)
  def call("Task.map2", arg_code), do: Helpers.runtime_ternary(Elmx.Runtime.Core.Task, "map2", arg_code)
  def call("Task.perform", arg_code), do: Helpers.runtime_binary(Elmx.Runtime.Core.Task, "perform", arg_code)
  def call("Process.spawn", arg_code), do: Helpers.runtime_unary(Elmx.Runtime.Core.Process, "spawn", arg_code)
  def call("Process.sleep", arg_code), do: Helpers.runtime_unary(Elmx.Runtime.Core.Process, "sleep", arg_code)
  def call("Process.kill", arg_code), do: Helpers.runtime_unary(Elmx.Runtime.Core.Process, "kill", arg_code)

  def call("Json.Decode.string", _arg_code), do: QualifiedCodegen.module_call(Elmx.Runtime.Json.Decode, "string", [])
  def call("Json.Decode.int", _arg_code), do: QualifiedCodegen.module_call(Elmx.Runtime.Json.Decode, "int", [])
  def call("Json.Decode.float", _arg_code), do: QualifiedCodegen.module_call(Elmx.Runtime.Json.Decode, "float", [])
  def call("Json.Decode.bool", _arg_code), do: QualifiedCodegen.module_call(Elmx.Runtime.Json.Decode, "bool", [])
  def call("Json.Decode.value", _arg_code), do: QualifiedCodegen.module_call(Elmx.Runtime.Json.Decode, "value", [])
  def call("Json.Decode.field", arg_code), do: Helpers.json_decode_binary("field", arg_code)
  def call("Json.Decode.at", arg_code), do: Helpers.json_decode_binary("at", arg_code)
  def call("Json.Decode.index", arg_code), do: Helpers.json_decode_binary("index", arg_code)
  def call("Json.Decode.list", arg_code), do: Helpers.json_decode_unary_builder("list", arg_code)
  def call("Json.Decode.array", arg_code), do: Helpers.json_decode_unary_builder("array", arg_code)
  def call("Json.Decode.null", arg_code), do: Helpers.json_decode_unary_builder("null", arg_code)
  def call("Json.Decode.nullable", arg_code), do: Helpers.json_decode_unary_builder("nullable", arg_code)
  def call("Json.Decode.maybe", arg_code), do: Helpers.json_decode_unary_builder("maybe", arg_code)
  def call("Json.Decode.fail", arg_code), do: Helpers.wrapped_runtime_unary(Elmx.Runtime.Json.Decode, "fail", arg_code)
  def call("Json.Decode.andThen", arg_code), do: Helpers.json_decode_binary("and_then", arg_code)
  def call("Json.Decode.lazy", arg_code), do: Helpers.json_decode_unary_builder("lazy", arg_code)
  def call("Json.Decode.dict", arg_code), do: Helpers.json_decode_unary_builder("dict", arg_code)

  def call("Json.Decode.keyValuePairs", arg_code),
    do: Helpers.json_decode_unary_builder("key_value_pairs", arg_code)

  def call("Json.Decode.map", arg_code), do: Helpers.json_decode_binary("map", arg_code)
  def call("Json.Decode.map2", arg_code), do: Helpers.runtime_ternary(Elmx.Runtime.Json.Decode, "map2", arg_code)
  def call("Json.Decode.map3", arg_code), do: Helpers.runtime_nary(Elmx.Runtime.Json.Decode, "map3", arg_code, 4)

  def call("Json.Decode.map4", arg_code), do: Helpers.json_map_n(Elmx.Runtime.Json.Decode, "map4", arg_code, 5)
  def call("Json.Decode.map5", arg_code), do: Helpers.json_map_n(Elmx.Runtime.Json.Decode, "map5", arg_code, 6)
  def call("Json.Decode.map6", arg_code), do: Helpers.json_map_n(Elmx.Runtime.Json.Decode, "map6", arg_code, 7)
  def call("Json.Decode.map7", arg_code), do: Helpers.json_map_n(Elmx.Runtime.Json.Decode, "map7", arg_code, 8)

  def call("Json.Decode.succeed", arg_code), do: Helpers.wrapped_runtime_unary(Elmx.Runtime.Json.Decode, "succeed", arg_code)
  def call("Json.Decode.oneOf", arg_code), do: Helpers.wrapped_runtime_unary(Elmx.Runtime.Json.Decode, "one_of", arg_code)
  def call("Json.Decode.decodeString", arg_code), do: Helpers.runtime_binary(Elmx.Runtime.Json.Decode, "decode_string", arg_code)
  def call("Json.Decode.decodeValue", arg_code), do: Helpers.runtime_binary(Elmx.Runtime.Json.Decode, "decode_value", arg_code)
  def call("Json.Decode.errorToString", arg_code), do: Helpers.runtime_unary(Elmx.Runtime.Json.Decode, "error_to_string", arg_code)
  def call(_target, _arg_code), do: :error
end