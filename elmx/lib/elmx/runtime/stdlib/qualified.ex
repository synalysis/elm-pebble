defmodule Elmx.Runtime.Stdlib.Qualified do
  @moduledoc false

  @spec call(String.t(), String.t()) :: {:ok, String.t()} | :error
  def call("List.filter", arg_code), do: list_core_hof("filter", arg_code)
  def call("List.map", arg_code), do: list_core_hof("map", arg_code)
  def call("List.filterMap", arg_code), do: list_core_hof("filter_map", arg_code)
  def call("List.concatMap", arg_code), do: list_core_hof("concat_map", arg_code)
  def call("List.sortBy", arg_code), do: list_core_hof("sort_by", arg_code)
  def call("List.sortWith", arg_code), do: list_core_hof("sort_with", arg_code)
  def call("List.sum", arg_code), do: unary("Elmx.Runtime.Core.list_sum", arg_code)
  def call("List.product", arg_code), do: unary("Elmx.Runtime.Core.list_product", arg_code)
  def call("List.maximum", arg_code), do: unary("Elmx.Runtime.Core.list_maximum", arg_code)
  def call("List.minimum", arg_code), do: unary("Elmx.Runtime.Core.list_minimum", arg_code)
  def call("List.any", arg_code), do: list_core_hof("any", arg_code)
  def call("List.all", arg_code), do: list_core_hof("all", arg_code)
  def call("List.foldl", arg_code), do: list_core_fold("foldl", arg_code)
  def call("List.foldr", arg_code), do: list_core_fold("foldr", arg_code)
  def call("List.repeat", arg_code), do: list_repeat(arg_code)
  def call("List.member", arg_code), do: list_member(arg_code)
  def call("List.sort", arg_code), do: unary("Elmx.Runtime.Core.sort", arg_code)
  def call("List.head", arg_code), do: unary("Elmx.Runtime.Core.list_head", arg_code)

  def call("List.indexedMap", arg_code) do
    case split_args(arg_code) do
      [fun, list] -> {:ok, "Elmx.Runtime.Core.indexed_map(#{fun}, #{list})"}
      [fun] -> {:ok, "fn elmx_list -> Elmx.Runtime.Core.indexed_map(#{fun}, elmx_list) end"}
      _ -> :error
    end
  end
  def call("List.range", arg_code) do
    case split_args(arg_code) do
      [first, last] -> {:ok, "Enum.to_list(#{first}..#{last})"}
      _ -> :error
    end
  end
  def call("String.fromInt", arg_code), do: unary("Integer.to_string", arg_code)
  def call("String.append", arg_code), do: binary_fn("Elmx.Runtime.Core.append", arg_code)
  def call("String.replace", arg_code), do: string_replace(arg_code)
  def call("String.split", arg_code), do: string_split(arg_code)
  def call("String.join", arg_code), do: string_join(arg_code)
  def call("String.contains", arg_code), do: string_binary("contains", arg_code)
  def call("String.startsWith", arg_code), do: string_binary("starts_with", arg_code)
  def call("String.endsWith", arg_code), do: string_binary("ends_with", arg_code)
  def call("String.repeat", arg_code), do: string_repeat(arg_code)
  def call("Basics.compare", arg_code), do: binary_fn("Elmx.Runtime.Core.basics_compare", arg_code)
  def call("String.length", arg_code), do: string_unary("length_val", arg_code)
  def call("String.reverse", arg_code), do: string_unary("reverse", arg_code)
  def call("String.words", arg_code), do: string_unary("words", arg_code)
  def call("String.lines", arg_code), do: string_unary("lines", arg_code)
  def call("String.trimLeft", arg_code), do: string_unary("trim_left", arg_code)
  def call("String.trimRight", arg_code), do: string_unary("trim_right", arg_code)
  def call("String.toInt", arg_code), do: string_to_int(arg_code)
  def call("String.toFloat", arg_code), do: string_to_float(arg_code)
  def call("String.fromFloat", arg_code), do: string_unary("from_float", arg_code)
  def call("String.slice", arg_code), do: string_slice(arg_code)
  def call("String.pad", arg_code), do: string_pad("pad", arg_code)
  def call("String.padLeft", arg_code), do: string_pad("pad_left", arg_code)
  def call("String.padRight", arg_code), do: string_pad("pad_right", arg_code)
  def call("String.cons", arg_code), do: string_binary("cons", arg_code)
  def call("String.uncons", arg_code), do: string_unary("uncons", arg_code)
  def call("String.toList", arg_code), do: string_unary("to_list", arg_code)
  def call("String.fromList", arg_code), do: string_unary("from_list", arg_code)
  def call("String.fromChar", arg_code), do: string_unary("from_char", arg_code)
  def call("Basics.not", arg_code), do: unary("not", arg_code)
  def call("Basics.abs", arg_code), do: unary("abs", arg_code)
  def call("Basics.min", arg_code), do: binary_fn("min", arg_code)
  def call("Basics.max", arg_code), do: binary_fn("max", arg_code)
  def call("Basics.modBy", arg_code), do: mod_by(arg_code)
  def call("Basics.remainderBy", arg_code), do: remainder_by(arg_code)
  def call("Maybe.withDefault", arg_code), do: maybe_with_default(arg_code)
  def call("Maybe.map", arg_code), do: maybe_map(arg_code)
  def call("Result.mapError", arg_code), do: result_map_error(arg_code)
  def call("Result.andThen", arg_code), do: result_and_then(arg_code)
  def call("Json.Encode.string", arg_code), do: unary("Elmx.Runtime.Json.Encode.string", arg_code)
  def call("Json.Encode.int", arg_code), do: unary("Elmx.Runtime.Json.Encode.int", arg_code)
  def call("Json.Encode.float", arg_code), do: unary("Elmx.Runtime.Json.Encode.float", arg_code)
  def call("Json.Encode.bool", arg_code), do: unary("Elmx.Runtime.Json.Encode.bool", arg_code)
  def call("Json.Encode.null", _arg_code), do: {:ok, "Elmx.Runtime.Json.Encode.null()"}
  def call("Json.Encode.encode", arg_code), do: binary_fn("Elmx.Runtime.Json.Encode.encode", arg_code)
  def call("Dict.get", arg_code), do: dict_get(arg_code)
  def call("Dict.insert", arg_code), do: dict_insert(arg_code)
  def call("Dict.remove", arg_code), do: dict_remove(arg_code)
  def call("Dict.member", arg_code), do: dict_member(arg_code)

  def call("Dict." <> rest, arg_code),
    do: collection_qualified("Elmx.Runtime.Core.Collections", "dict", rest, arg_code)

  def call("Set." <> rest, arg_code),
    do: collection_qualified("Elmx.Runtime.Core.Collections", "set", rest, arg_code)

  def call("Array." <> rest, arg_code),
    do: collection_qualified("Elmx.Runtime.Core.Collections", "array", rest, arg_code)

  def call("Task.succeed", arg_code), do: unary("Elmx.Runtime.Core.Task.succeed", arg_code)
  def call("Task.fail", arg_code), do: unary("Elmx.Runtime.Core.Task.fail", arg_code)
  def call("Task.map2", arg_code), do: ternary("Elmx.Runtime.Core.Task.map2", arg_code)
  def call("Task.perform", arg_code), do: binary_fn("Elmx.Runtime.Core.Task.perform", arg_code)
  def call("Process.spawn", arg_code), do: unary("Elmx.Runtime.Core.Process.spawn", arg_code)
  def call("Process.sleep", arg_code), do: unary("Elmx.Runtime.Core.Process.sleep", arg_code)
  def call("Process.kill", arg_code), do: unary("Elmx.Runtime.Core.Process.kill", arg_code)

  def call("Json.Decode.string", _arg_code), do: {:ok, "Elmx.Runtime.Json.Decode.string()"}
  def call("Json.Decode.int", _arg_code), do: {:ok, "Elmx.Runtime.Json.Decode.int()"}
  def call("Json.Decode.float", _arg_code), do: {:ok, "Elmx.Runtime.Json.Decode.float()"}
  def call("Json.Decode.bool", _arg_code), do: {:ok, "Elmx.Runtime.Json.Decode.bool()"}
  def call("Json.Decode.value", _arg_code), do: {:ok, "Elmx.Runtime.Json.Decode.value()"}
  def call("Json.Decode.field", arg_code), do: json_decode_binary("field", arg_code)
  def call("Json.Decode.at", arg_code), do: json_decode_binary("at", arg_code)
  def call("Json.Decode.index", arg_code), do: json_decode_binary("index", arg_code)
  def call("Json.Decode.list", arg_code), do: json_decode_unary_builder("list", arg_code)
  def call("Json.Decode.array", arg_code), do: json_decode_unary_builder("array", arg_code)
  def call("Json.Decode.null", arg_code), do: json_decode_unary_builder("null", arg_code)
  def call("Json.Decode.nullable", arg_code), do: json_decode_unary_builder("nullable", arg_code)
  def call("Json.Decode.maybe", arg_code), do: json_decode_unary_builder("maybe", arg_code)
  def call("Json.Decode.fail", arg_code), do: unary("Elmx.Runtime.Json.Decode.fail", arg_code)
  def call("Json.Decode.andThen", arg_code), do: json_decode_binary("and_then", arg_code)
  def call("Json.Decode.lazy", arg_code), do: json_decode_unary_builder("lazy", arg_code)
  def call("Json.Decode.dict", arg_code), do: json_decode_unary_builder("dict", arg_code)

  def call("Json.Decode.keyValuePairs", arg_code),
    do: json_decode_unary_builder("key_value_pairs", arg_code)

  def call("Json.Decode.map", arg_code), do: json_decode_binary("map", arg_code)
  def call("Json.Decode.map2", arg_code), do: ternary("Elmx.Runtime.Json.Decode.map2", arg_code)
  def call("Json.Decode.map3", arg_code), do: quaternary("Elmx.Runtime.Json.Decode.map3", arg_code)
  def call("Json.Decode.map4", arg_code), do: json_map_n("Elmx.Runtime.Json.Decode.map4", arg_code, 5)
  def call("Json.Decode.map5", arg_code), do: json_map_n("Elmx.Runtime.Json.Decode.map5", arg_code, 6)
  def call("Json.Decode.map6", arg_code), do: json_map_n("Elmx.Runtime.Json.Decode.map6", arg_code, 7)
  def call("Json.Decode.map7", arg_code), do: json_map_n("Elmx.Runtime.Json.Decode.map7", arg_code, 8)
  def call("Json.Decode.succeed", arg_code), do: unary("Elmx.Runtime.Json.Decode.succeed", arg_code)
  def call("Json.Decode.oneOf", arg_code), do: unary("Elmx.Runtime.Json.Decode.one_of", arg_code)
  def call("Json.Decode.decodeString", arg_code),
    do: binary_fn("Elmx.Runtime.Json.Decode.decode_string", arg_code)

  def call("Json.Decode.decodeValue", arg_code), do: binary_fn("Elmx.Runtime.Json.Decode.decode_value", arg_code)
  def call("Json.Decode.errorToString", arg_code), do: unary("Elmx.Runtime.Json.Decode.error_to_string", arg_code)
  def call(_target, _arg_code), do: :error

  defp list_core_hof(core_fun, arg_code) do
    case split_args(arg_code) do
      [fun_expr, list] ->
        {:ok, "Elmx.Runtime.Core.#{core_fun}(#{fun_expr}, #{list})"}

      [fun_expr] ->
        {:ok, "fn elmx_list -> Elmx.Runtime.Core.#{core_fun}(#{fun_expr}, elmx_list) end"}

      _ ->
        :error
    end
  end

  defp list_core_fold(core_fun, arg_code) do
    case split_args(arg_code) do
      [fun_expr, acc, list] ->
        {:ok, "Elmx.Runtime.Core.#{core_fun}(#{fun_expr}, #{acc}, #{list})"}

      [fun_expr, acc] ->
        {:ok, "fn elmx_list -> Elmx.Runtime.Core.#{core_fun}(#{fun_expr}, #{acc}, elmx_list) end"}

      [fun_expr] ->
        {:ok,
         "fn elmx_acc, elmx_list -> Elmx.Runtime.Core.#{core_fun}(#{fun_expr}, elmx_acc, elmx_list) end"}

      _ ->
        :error
    end
  end

  defp list_repeat(arg_code) do
    case split_args(arg_code) do
      [n, value] -> {:ok, "Elmx.Runtime.Core.list_repeat(#{n}, #{value})"}
      _ -> :error
    end
  end

  defp list_member(arg_code) do
    case split_args(arg_code) do
      [value, list] -> {:ok, "Elmx.Runtime.Core.member(#{value}, #{list})"}
      [value] -> {:ok, "fn elmx_list -> Elmx.Runtime.Core.member(#{value}, elmx_list) end"}
      _ -> :error
    end
  end

  defp dict_get(arg_code) do
    case split_args(arg_code) do
      [key, dict] -> {:ok, "Elmx.Runtime.Core.Collections.dict_get(#{key}, #{dict})"}
      [key] -> {:ok, "fn elmx_dict -> Elmx.Runtime.Core.Collections.dict_get(#{key}, elmx_dict) end"}
      _ -> :error
    end
  end

  defp dict_insert(arg_code) do
    case split_args(arg_code) do
      [key, value, dict] ->
        {:ok, "Elmx.Runtime.Core.Collections.dict_insert(#{key}, #{value}, #{dict})"}

      [key, value] ->
        {:ok,
         "fn elmx_dict -> Elmx.Runtime.Core.Collections.dict_insert(#{key}, #{value}, elmx_dict) end"}

      _ ->
        :error
    end
  end

  defp dict_remove(arg_code) do
    case split_args(arg_code) do
      [key, dict] -> {:ok, "Elmx.Runtime.Core.Collections.dict_remove(#{key}, #{dict})"}
      [key] -> {:ok, "fn elmx_dict -> Elmx.Runtime.Core.Collections.dict_remove(#{key}, elmx_dict) end"}
      _ -> :error
    end
  end

  defp dict_member(arg_code) do
    case split_args(arg_code) do
      [key, dict] -> {:ok, "Elmx.Runtime.Core.Collections.dict_member(#{key}, #{dict})"}
      [key] -> {:ok, "fn elmx_dict -> Elmx.Runtime.Core.Collections.dict_member(#{key}, elmx_dict) end"}
      _ -> :error
    end
  end

  defp unary(op, arg_code), do: {:ok, "(#{op}(#{pick(arg_code, 0)}))"}

  defp binary_fn(op, arg_code) do
    case split_args(arg_code) do
      [left, right] -> {:ok, "#{op}(#{left}, #{right})"}
      _ -> :error
    end
  end

  defp string_replace(arg_code) do
    mod = "Elmx.Runtime.Core.Strings"

    case split_args(arg_code) do
      [before, after_str, text] ->
        {:ok, "#{mod}.replace(#{before}, #{after_str}, #{text})"}

      [before, after_str] ->
        {:ok, "fn elmx_str -> #{mod}.replace(#{before}, #{after_str}, elmx_str) end"}

      _ ->
        :error
    end
  end

  defp string_split(arg_code) do
    mod = "Elmx.Runtime.Core.Strings"

    case split_args(arg_code) do
      [sep, text] -> {:ok, "#{mod}.split(#{sep}, #{text})"}
      [sep] -> {:ok, "fn elmx_str -> #{mod}.split(#{sep}, elmx_str) end"}
      _ -> :error
    end
  end

  defp string_join(arg_code) do
    mod = "Elmx.Runtime.Core.Strings"

    case split_args(arg_code) do
      [sep, list] -> {:ok, "#{mod}.join(#{sep}, #{list})"}
      [sep] -> {:ok, "fn elmx_list -> #{mod}.join(#{sep}, elmx_list) end"}
      _ -> :error
    end
  end

  defp string_binary(fun, arg_code) do
    mod = "Elmx.Runtime.Core.Strings"

    case split_args(arg_code) do
      [fixed, text] -> {:ok, "#{mod}.#{fun}(#{fixed}, #{text})"}
      [fixed] -> {:ok, "fn elmx_str -> #{mod}.#{fun}(#{fixed}, elmx_str) end"}
      _ -> :error
    end
  end

  defp string_repeat(arg_code) do
    mod = "Elmx.Runtime.Core.Strings"

    case split_args(arg_code) do
      [n, text] -> {:ok, "#{mod}.repeat(#{n}, #{text})"}
      [n] -> {:ok, "fn elmx_str -> #{mod}.repeat(#{n}, elmx_str) end"}
      _ -> :error
    end
  end

  defp string_unary(fun, arg_code) do
    mod = "Elmx.Runtime.Core.Strings"

    case split_args(arg_code) do
      [text] -> {:ok, "#{mod}.#{fun}(#{text})"}
      [] -> {:ok, "fn elmx_str -> #{mod}.#{fun}(elmx_str) end"}
      _ -> :error
    end
  end

  defp string_slice(arg_code) do
    mod = "Elmx.Runtime.Core.Strings"

    case split_args(arg_code) do
      [start, len, text] -> {:ok, "#{mod}.slice(#{start}, #{len}, #{text})"}
      _ -> :error
    end
  end

  defp string_pad(fun, arg_code) do
    mod = "Elmx.Runtime.Core.Strings"

    case split_args(arg_code) do
      [n, ch, text] -> {:ok, "#{mod}.#{fun}(#{n}, #{ch}, #{text})"}
      _ -> :error
    end
  end

  defp json_decode_binary(fun, arg_code) do
    mod = "Elmx.Runtime.Json.Decode"

    case split_args(arg_code) do
      [a, b] -> {:ok, "#{mod}.#{fun}(#{a}, #{b})"}
      [a] -> {:ok, "fn elmx_dec -> #{mod}.#{fun}(#{a}, elmx_dec) end"}
      _ -> :error
    end
  end

  defp json_decode_unary_builder(fun, arg_code) do
    mod = "Elmx.Runtime.Json.Decode"

    case split_args(arg_code) do
      [inner] -> {:ok, "#{mod}.#{fun}(#{inner})"}
      [] -> {:ok, "fn elmx_inner -> #{mod}.#{fun}(elmx_inner) end"}
      _ -> :error
    end
  end

  defp ternary(op, arg_code) do
    case split_args(arg_code) do
      [a, b, c] -> {:ok, "#{op}(#{a}, #{b}, #{c})"}
      _ -> :error
    end
  end

  defp quaternary(op, arg_code) do
    case split_args(arg_code) do
      [a, b, c, d] -> {:ok, "#{op}(#{a}, #{b}, #{c}, #{d})"}
      _ -> :error
    end
  end

  defp json_map_n(op, arg_code, count) do
    case split_args(arg_code) do
      args when length(args) == count -> {:ok, "#{op}(#{Enum.join(args, ", ")})"}
      _ -> :error
    end
  end

  defp mod_by(arg_code) do
    case split_args(arg_code) do
      [divisor, value] -> {:ok, "Integer.mod(#{value}, #{divisor})"}
      _ -> :error
    end
  end

  defp remainder_by(arg_code) do
    case split_args(arg_code) do
      [divisor, value] -> {:ok, "rem(#{value}, #{divisor})"}
      _ -> :error
    end
  end

  defp maybe_with_default(arg_code) do
    case split_args(arg_code) do
      [default, maybe] ->
        code = "(case " <> maybe <> " do :Nothing -> " <> default <> "; other -> elem(other, 1) end)"
        {:ok, code}

      _ ->
        :error
    end
  end

  defp maybe_map(arg_code) do
    case split_args(arg_code) do
      [fun, maybe] ->
        code =
          "(case " <> maybe <> " do :Nothing -> :Nothing; other -> {:Just, (" <> fun <> ").(elem(other, 1))} end)"

        {:ok, code}

      _ ->
        :error
    end
  end

  defp string_to_int(arg_code) do
    arg = pick(arg_code, 0)

    {:ok,
     "(case Integer.parse(#{arg}) do {n, _} -> n; :error -> 0 end)"}
  end

  defp string_to_float(arg_code) do
    arg = pick(arg_code, 0)

    {:ok,
     "(case Float.parse(#{arg}) do {f, _} -> f; :error -> 0.0 end)"}
  end

  defp result_map_error(arg_code) do
    case split_args(arg_code) do
      [fun] -> {:ok, "fn result -> Elmx.Runtime.Core.result_map_error(#{fun}, result) end"}
      [fun, result] -> {:ok, "Elmx.Runtime.Core.result_map_error(#{fun}, #{result})"}
      _ -> :error
    end
  end

  defp result_and_then(arg_code) do
    case split_args(arg_code) do
      [fun] -> {:ok, "fn result -> Elmx.Runtime.Core.result_and_then(#{fun}, result) end"}
      [fun, result] -> {:ok, "Elmx.Runtime.Core.result_and_then(#{fun}, #{result})"}
      _ -> :error
    end
  end

  defp pick(arg_code, index), do: Enum.at(split_args(arg_code), index) || "0"

  defp split_args(arg_code) when is_binary(arg_code) do
    Elmx.Runtime.Stdlib.split_top_level_args(arg_code)
  end

  defp collection_qualified(module, prefix, op, arg_code) when is_binary(op) do
    fun = prefix <> "_" <> Macro.underscore(op)
    {:ok, "#{module}.#{fun}(#{arg_code})"}
  end
end
