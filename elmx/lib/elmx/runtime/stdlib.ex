defmodule Elmx.Runtime.Stdlib do
  @moduledoc """
  Stdlib and runtime intrinsic dispatch for generated Elixir code.

  Qualified Elm calls resolve through `qualified_call/2`: `special_call/2` first (Maybe/Result,
  `Debug`, `Time`, Pebble stubs), then `Stdlib.Qualified.call/2`. IR emit uses the same path via
  `Emit.Qualified.compile_qualified_call_fallback_string/4`. Registry intrinsics use
  `Generator.compile_call/2` and `CodegenRefs` module paths instead.
  """

  alias Elmx.Runtime.CodegenRefs
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

  @maybe_result_special_targets ~w(
    Maybe.withDefault
    Maybe.map
    Maybe.andThen
    Result.mapError
    Result.andThen
  )

  def special_call(target, arg_code) when target in @maybe_result_special_targets do
    QualifiedCalls.call(target, IO.iodata_to_binary(arg_code))
  end

  def special_call("List.head", arg_code), do: {:ok, "List.first(#{arg_code})"}
  def special_call("head", arg_code), do: {:ok, "List.first(#{arg_code})"}

  def special_call("List.foldl", arg_code) do
    case split_top_level_args(arg_code) do
      ["__add__", acc, list] ->
        {:ok, "Enum.reduce(#{list}, #{acc}, fn a, b -> a + b end)"}

      [fun, acc, list] ->
        {:ok, "#{CodegenRefs.core()}.foldl(#{fun}, #{acc}, #{list})"}

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

  @basics_qualified_special_targets ~w(
    Basics.modBy
    Basics.remainderBy
    Basics.abs
    Basics.min
    Basics.max
    Basics.not
    Basics.negate
  )

  def special_call(target, arg_code) when target in @basics_qualified_special_targets do
    QualifiedCalls.call(target, IO.iodata_to_binary(arg_code))
  end

  def special_call("modBy", arg_code), do: special_call("Basics.modBy", arg_code)
  def special_call("remainderBy", arg_code), do: special_call("Basics.remainderBy", arg_code)
  def special_call("abs", arg_code), do: special_call("Basics.abs", arg_code)
  def special_call("min", arg_code), do: special_call("Basics.min", arg_code)
  def special_call("max", arg_code), do: special_call("Basics.max", arg_code)

  def special_call("Platform.Cmd.batch", arg_code),
    do: {:ok, "#{CodegenRefs.values()}.cmd_batch([#{arg_code}])"}

  def special_call("Pebble.Cmd.batch", arg_code), do: special_call("Platform.Cmd.batch", arg_code)

  def special_call("Json.Decode.errorToString", _arg_code),
    do: {:ok, "&#{CodegenRefs.json_decode()}.error_to_string/1"}

  def special_call("Debug.log", arg_code) do
    case split_top_level_args(arg_code) do
      [label, value] -> {:ok, "#{CodegenRefs.core_debug()}.log(#{label}, #{value})"}
      _ -> :error
    end
  end

  def special_call("Debug.todo", arg_code) do
    case split_top_level_args(arg_code) do
      [label] -> {:ok, "#{CodegenRefs.core_debug()}.todo(#{label})"}
      _ -> :error
    end
  end

  def special_call("Time.now", _arg_code), do: {:ok, "#{CodegenRefs.core_time()}.now()"}
  def special_call("Time.getZoneName", _arg_code), do: {:ok, "#{CodegenRefs.core_time()}.get_zone_name()"}

  def special_call("Debug.toString", arg_code) do
    case split_top_level_args(arg_code) do
      [value] -> {:ok, "#{CodegenRefs.core_debug()}.to_string(#{value})"}
      _ -> :error
    end
  end

  def special_call(target, _arg_code) do
    if Pebble.special_call?(target), do: Pebble.special_call_code(target), else: :error
  end

  @spec handles_qualified?(String.t()) :: boolean()
  def handles_qualified?(target) when is_binary(target), do: QualifiedCalls.handles?(target)

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
    |> then(&runtime_call_parts(function, &1))
  end

  defp runtime_call_dispatch(function, args) when is_binary(function) and is_list(args) do
    args = Enum.map(args, &IO.iodata_to_binary/1)

    case Generator.compile_call(function, args) do
      {:ok, code} ->
        code

      :error ->
        joined = Enum.join(args, ", ")

        if String.starts_with?(function, "elmx_") do
          "#{CodegenRefs.pebble()}.runtime_dispatch(#{inspect(function)}, [#{joined}])"
        else
          "#{CodegenRefs.pebble()}.runtime_call(#{inspect(function)}, #{joined})"
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
end
