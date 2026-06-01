defmodule Elmx.Runtime.Stdlib do
  @moduledoc """
  Stdlib and runtime intrinsic dispatch for generated Elixir code.
  """

  alias Elmx.Runtime.Generator
  alias Elmx.Runtime.Pebble
  alias Elmx.Runtime.Stdlib.Qualified, as: QualifiedCalls

  @spec special_call(String.t(), iodata()) :: {:ok, String.t()} | :error
  def special_call("Basics.identity", arg_code), do: {:ok, to_string(arg_code)}
  def special_call("identity", arg_code), do: {:ok, to_string(arg_code)}

  def special_call("Basics.always", arg_code) do
    {:ok, "fn _other -> #{arg_code} end"}
  end

  def special_call("always", arg_code) do
    {:ok, "fn _other -> #{arg_code} end"}
  end

  def special_call("Maybe.withDefault", arg_code) do
    parts = split_top_level_args(arg_code)

    case parts do
      [default, maybe] ->
        {:ok,
         "Elmx.Runtime.Core.maybe_with_default(#{default}, #{maybe})"}

      _ ->
        :error
    end
  end

  def special_call("Maybe.map", arg_code) do
    case split_top_level_args(arg_code) do
      [fun, maybe] ->
        {:ok, "Elmx.Runtime.Core.maybe_map(#{fun}, #{maybe})"}

      _ ->
        :error
    end
  end

  def special_call("Maybe.andThen", arg_code) do
    case split_top_level_args(arg_code) do
      [fun, maybe] ->
        {:ok, "Elmx.Runtime.Core.maybe_and_then(#{fun}, #{maybe})"}

      _ ->
        :error
    end
  end

  def special_call("Result.mapError", arg_code) do
    case split_top_level_args(arg_code) do
      [fun] ->
        {:ok, "fn result -> Elmx.Runtime.Core.result_map_error(#{fun}, result) end"}

      [fun, result] ->
        {:ok, "Elmx.Runtime.Core.result_map_error(#{fun}, #{result})"}

      _ ->
        :error
    end
  end

  def special_call("List.head", arg_code), do: {:ok, "List.first(#{arg_code})"}
  def special_call("head", arg_code), do: {:ok, "List.first(#{arg_code})"}

  def special_call("List.foldl", arg_code) do
    case split_top_level_args(arg_code) do
      ["__add__", acc, list] ->
        {:ok, "Enum.reduce(#{list}, #{acc}, fn a, b -> a + b end)"}

      [fun, acc, list] ->
        {:ok, "Elmx.Runtime.Core.foldl(#{fun}, #{acc}, #{list})"}

      _ ->
        :error
    end
  end

  def special_call("Tuple.first", arg_code), do: {:ok, "elem(#{arg_code}, 0)"}
  def special_call("Tuple.second", arg_code), do: {:ok, "elem(#{arg_code}, 1)"}
  def special_call("String.length", arg_code), do: {:ok, "String.length(#{arg_code})"}
  def special_call("Char.fromCode", arg_code), do: {:ok, "<<#{arg_code}::utf8>>"}
  def special_call("Char.toCode", arg_code), do: {:ok, "hd(String.to_charlist(#{arg_code}))"}
  def special_call("String.fromInt", arg_code), do: {:ok, "Integer.to_string(#{arg_code})"}
  def special_call("fromInt", arg_code), do: {:ok, "Integer.to_string(#{arg_code})"}

  def special_call("Basics.modBy", arg_code), do: mod_by(arg_code)
  def special_call("modBy", arg_code), do: mod_by(arg_code)
  def special_call("Basics.remainderBy", arg_code), do: remainder_by(arg_code)
  def special_call("remainderBy", arg_code), do: remainder_by(arg_code)

  def special_call("Basics.abs", arg_code), do: {:ok, "abs(#{arg_code})"}
  def special_call("abs", arg_code), do: {:ok, "abs(#{arg_code})"}

  def special_call("Basics.min", arg_code), do: binary_op_special("min", arg_code)
  def special_call("min", arg_code), do: binary_op_special("min", arg_code)
  def special_call("Basics.max", arg_code), do: binary_op_special("max", arg_code)
  def special_call("max", arg_code), do: binary_op_special("max", arg_code)

  def special_call("Platform.Cmd.batch", arg_code),
    do: {:ok, "Elmx.Runtime.Values.cmd_batch([#{arg_code}])"}

  def special_call("Pebble.Cmd.batch", arg_code), do: special_call("Platform.Cmd.batch", arg_code)

  def special_call("Json.Decode.errorToString", _arg_code),
    do: {:ok, "&Elmx.Runtime.Json.Decode.error_to_string/1"}

  def special_call("Debug.log", arg_code) do
    case split_top_level_args(arg_code) do
      [label, value] -> {:ok, "Elmx.Runtime.Core.Debug.log(#{label}, #{value})"}
      _ -> :error
    end
  end

  def special_call("Debug.todo", arg_code) do
    case split_top_level_args(arg_code) do
      [label] -> {:ok, "Elmx.Runtime.Core.Debug.todo(#{label})"}
      _ -> :error
    end
  end

  def special_call("Debug.toString", arg_code) do
    case split_top_level_args(arg_code) do
      [value] -> {:ok, "Elmx.Runtime.Core.Debug.to_string(#{value})"}
      _ -> :error
    end
  end

  def special_call("Result.andThen", arg_code) do
    case split_top_level_args(arg_code) do
      [fun] ->
        {:ok, "fn result -> Elmx.Runtime.Core.result_and_then(#{fun}, result) end"}

      [fun, result] ->
        {:ok, "Elmx.Runtime.Core.result_and_then(#{fun}, #{result})"}

      _ ->
        :error
    end
  end

  def special_call(target, _arg_code) do
    if Pebble.special_call?(target), do: Pebble.special_call_code(target), else: :error
  end

  @spec qualified_call(String.t(), String.t()) :: {:ok, String.t()} | :error
  def qualified_call(target, arg_code) when is_binary(target) and is_binary(arg_code) do
    case special_call(target, arg_code) do
      {:ok, code} -> {:ok, code}
      :error -> QualifiedCalls.call(target, arg_code)
    end
  end

  @spec runtime_call_parts(String.t(), [String.t()]) :: String.t()
  def runtime_call_parts(function, parts) when is_binary(function) and is_list(parts) do
    case Elmx.Runtime.Generator.compile_call(function, parts) do
      {:ok, code} ->
        code

      :error ->
        runtime_call_dispatch(function, parts)
    end
  end

  @spec runtime_call(String.t(), iodata()) :: String.t()
  def runtime_call(function, arg_code) when is_binary(function) do
    arg_code
    |> IO.iodata_to_binary()
    |> split_top_level_args()
    |> then(&runtime_call_dispatch(function, &1))
  end

  defp runtime_call_dispatch(function, args) when is_binary(function) and is_list(args) do
    args = Enum.map(args, &IO.iodata_to_binary/1)

    case function do
      "elmc_basics_not" -> unary("not", args)
      "elmc_basics_negate" -> unary("-", args)
      "elmc_basics_abs" -> "abs(#{pick(args, 0, "0")})"
      "elmc_basics_max" -> binary("max", args)
      "elmc_basics_min" -> binary("min", args)
      "elmc_basics_mod_by" -> binary("rem", args)
      "elmc_basics_clamp" -> clamp(args)
      "elmx_cmd_batch" -> "Elmx.Runtime.Values.cmd_batch([#{Enum.join(args, ", ")}])"
      "elmx_ui_named_color" -> "Elmx.Runtime.Pebble.Ui.named_color(#{pick(args, 0, ~s("black"))})"
      "elmx_core_maybe_with_default" -> "Elmx.Runtime.Core.maybe_with_default(#{pick(args, 0, "0")}, #{pick(args, 1, ":Nothing")})"
      "elmx_core_maybe_map" -> "Elmx.Runtime.Core.maybe_map(#{pick(args, 0, "&Function.identity/1")}, #{pick(args, 1, ":Nothing")})"
      "elmx_core_maybe_and_then" -> "Elmx.Runtime.Core.maybe_and_then(#{pick(args, 0, "&Function.identity/1")}, #{pick(args, 1, ":Nothing")})"
      "elmx_core_maybe_map2" -> "Elmx.Runtime.Core.maybe_map2(#{pick(args, 1, ":Nothing")}, #{pick(args, 2, ":Nothing")}, #{pick(args, 0, "&Function.identity/2")})"
      "elmx_core_result_map" ->
        "Elmx.Runtime.Core.result_map(#{pick(args, 0, "&Function.identity/1")}, #{pick(args, 1, "{:Err, nil}")})"

      "elmx_core_result_with_default" -> "Elmx.Runtime.Core.result_with_default(#{pick(args, 0, "0")}, #{pick(args, 1, "{:Err, nil}")})"
      "elmx_core_result_and_then" ->
        "Elmx.Runtime.Core.result_and_then(#{pick(args, 0, "&Function.identity/1")}, #{pick(args, 1, "{:Err, nil}")})"
      "elmx_core_result_map_error" -> "Elmx.Runtime.Core.result_map_error(#{pick(args, 0, "&Function.identity/1")}, #{pick(args, 1, "{:Err, nil}")})"
      "elmx_core_random_generator" -> "Elmx.Runtime.Core.random_generator(#{pick(args, 0, "0")}, #{pick(args, 1, "1")})"
      "elmx_cmd_random_generate" ->
        "Elmx.Runtime.Pebble.runtime_dispatch(\"elmx_cmd_random_generate\", [#{Enum.join(args, ", ")}])"

      "elmx_list_repeat" ->
        "Elmx.Runtime.Pebble.runtime_dispatch(\"elmx_list_repeat\", [#{Enum.join(args, ", ")}])"

      "elmx_basics_to_float" ->
        "Elmx.Runtime.Pebble.runtime_dispatch(\"elmx_basics_to_float\", [#{Enum.join(args, ", ")}])"

      "elmx_basics_floor" -> unary("floor", args)
      "elmx_basics_ceiling" -> unary("ceil", args)
      "elmx_basics_round" -> unary("round", args)
      "elmx_basics_truncate" -> unary("trunc", args)

      other ->
        case Generator.compile_call(other, args) do
          {:ok, code} ->
            code

          :error ->
            joined = Enum.join(args, ", ")

            if String.starts_with?(other, "elmx_") do
              "Elmx.Runtime.Pebble.runtime_dispatch(#{inspect(other)}, [#{joined}])"
            else
              "Elmx.Runtime.Pebble.runtime_call(#{inspect(other)}, #{joined})"
            end
        end
    end
  end

  @spec call(String.t(), iodata()) :: String.t()
  def call("__mul__", arg_code), do: binary_op("*", arg_code)
  def call("__add__", arg_code), do: binary_op("+", arg_code)
  def call("__sub__", arg_code), do: binary_op("-", arg_code)
  def call("__fdiv__", arg_code), do: binary_op("/", arg_code)
  def call("__idiv__", arg_code), do: binary_op("div", arg_code)
  def call("__append__", arg_code), do: binary_op("++", arg_code)
  def call(name, arg_code), do: "raise \"unsupported internal call #{name}(#{arg_code})\""

  defp binary_op(op, arg_code) do
    case split_top_level_args(arg_code) do
      [left, right] -> "(#{left} #{op} #{right})"
      _ -> "raise \"bad arity for #{op}\""
    end
  end

  defp unary(op, args), do: "(#{op}(#{pick(args, 0, "false")}))"
  defp binary(op, args), do: "(#{op}(#{pick(args, 0, "0")}, #{pick(args, 1, "0")}))"

  defp clamp(args) do
    case args do
      [lo, x, hi] -> "min(max(#{x}, #{lo}), #{hi})"
      _ -> "0"
    end
  end

  defp pick(args, index, default) do
    Enum.at(args, index) || default
  end

  @doc false
  def split_top_level_args(arg_code) when is_binary(arg_code) do
    arg_code
    |> String.to_charlist()
    |> split_top_level_commas([], 0, [])
    |> Enum.reverse()
    |> Enum.map(fn chars -> chars |> List.to_string() |> String.trim() end)
    |> Enum.reject(&(&1 == ""))
  end

  defp split_top_level_commas([], parts, _depth, current),
    do: [current | parts]

  defp split_top_level_commas([?, | rest], parts, 0, current),
    do: split_top_level_commas(rest, [current | parts], 0, [])

  defp split_top_level_commas([char | rest], parts, depth, current) do
    next_depth =
      case char do
        ?( -> depth + 1
        ?) -> depth - 1
        ?[ -> depth + 1
        ?] -> depth - 1
        ?{ -> depth + 1
        ?} -> depth - 1
        _ -> depth
      end

    split_top_level_commas(rest, parts, next_depth, current ++ [char])
  end

  defp mod_by(arg_code) do
    case split_top_level_args(arg_code) do
      [divisor, value] -> {:ok, "Integer.mod(#{value}, #{divisor})"}
      _ -> :error
    end
  end

  defp remainder_by(arg_code) do
    case split_top_level_args(arg_code) do
      [divisor, value] -> {:ok, "rem(#{value}, #{divisor})"}
      _ -> :error
    end
  end

  defp binary_op_special(op, arg_code) do
    case split_top_level_args(arg_code) do
      [left, right] -> {:ok, "#{op}(#{left}, #{right})"}
      _ -> :error
    end
  end
end
