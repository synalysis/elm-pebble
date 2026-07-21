defmodule Elmx.Backend.QualifiedRewrite do
  @moduledoc """
  Rewrites `qualified_call` IR to expression nodes (mirrors `elmc` `special_value_from_target/2`).
  """

  alias Elmx.Types

  @spec rewrite(String.t(), list()) :: Types.rewrite_result()
  def rewrite(target, args) when is_binary(target) and is_list(args) do
    target = normalize_target(target)

    case operator_call_rewrite(target, args) do
      {:ok, _} = ok ->
        ok

      :error ->
        rewrite_qualified(target, args)
    end
  end

  @doc """
  Maps `Elm.Kernel.*` stdlib shorthands back to Elm module names used by emit clauses.
  """
  @spec normalize_target(String.t()) :: String.t()
  def normalize_target(target) when is_binary(target) do
    target
    |> strip_pkg_mangle_prefix()
    |> Elmx.Runtime.Pebble.SpecialValues.canonical_target()
    |> denormalize_kernel_shorthand()
    |> denormalize_utils_alias()
  end

  defp strip_pkg_mangle_prefix("Pkg." <> rest) do
    case String.split(rest, ".", parts: 2) do
      [_pkg, module_target] -> module_target
      _ -> rest
    end
  end

  defp strip_pkg_mangle_prefix(target), do: target

  defp rewrite_qualified(target, args) do
    case {target, args} do
      {"Maybe.withDefault", [default]} ->
        curried("elmx_core_maybe_with_default", [default], "__m")

      {"Maybe.withDefault", [default, maybe]} ->
        runtime2("elmx_core_maybe_with_default", [default, maybe])

      {"Maybe.map", [fun]} ->
        curried("elmx_core_maybe_map", [fun], "__m")

      {"Maybe.map", [fun, maybe]} ->
        runtime2("elmx_core_maybe_map", [fun, maybe])

      {"Maybe.map2", [fun, a, b]} ->
        runtime3("elmx_core_maybe_map2", [fun, a, b])

      {"Maybe.map3", [fun, a, b, c]} ->
        runtime4("elmx_core_maybe_map3", [fun, a, b, c])

      {"Maybe.map4", [fun, a, b, c, d]} ->
        runtime5("elmx_core_maybe_map4", [fun, a, b, c, d])

      {"Maybe.map5", [fun, a, b, c, d, e]} ->
        runtime6("elmx_core_maybe_map5", [fun, a, b, c, d, e])

      {"Maybe.andThen", [fun]} ->
        curried("elmx_core_maybe_and_then", [fun], "__m")

      {"Maybe.andThen", [fun, maybe]} ->
        runtime2("elmx_core_maybe_and_then", [fun, maybe])

      {"Result.map", [fun]} ->
        curried("elmx_core_result_map", [fun], "__r")

      {"Result.map", [fun, result]} ->
        runtime2("elmx_core_result_map", [fun, result])

      {"Result.map2", [fun, a, b]} ->
        runtime3("elmx_core_result_map2", [fun, a, b])

      {"Result.map3", [fun, a, b, c]} ->
        runtime4("elmx_core_result_map3", [fun, a, b, c])

      {"Result.map4", [fun, a, b, c, d]} ->
        runtime5("elmx_core_result_map4", [fun, a, b, c, d])

      {"Result.map5", [fun, a, b, c, d, e]} ->
        runtime6("elmx_core_result_map5", [fun, a, b, c, d, e])

      {"Result.withDefault", [default]} ->
        curried("elmx_core_result_with_default", [default], "__r")

      {"Result.withDefault", [default, result]} ->
        runtime2("elmx_core_result_with_default", [default, result])

      {"Result.andThen", [fun]} ->
        curried("elmx_core_result_and_then", [fun], "__r")

      {"Result.andThen", [fun, result]} ->
        runtime2("elmx_core_result_and_then", [fun, result])

      {"Result.mapError", [fun]} ->
        curried("elmx_core_result_map_error", [fun], "__r")

      {"Result.mapError", [fun, result]} ->
        runtime2("elmx_core_result_map_error", [fun, result])

      {"Task.map", [fun]} ->
        curried("elmx_core_task_map", [fun], "__t")

      {"Task.map", [fun, task]} ->
        runtime2("elmx_core_task_map", [fun, task])

      {"Task.map2", [fun, a, b]} ->
        runtime3("elmx_core_task_map2", [fun, a, b])

      {"Task.map3", [fun, a, b, c]} ->
        runtime4("elmx_core_task_map3", [fun, a, b, c])

      {"Task.map4", [fun, a, b, c, d]} ->
        runtime5("elmx_core_task_map4", [fun, a, b, c, d])

      {"Task.map5", [fun, a, b, c, d, e]} ->
        runtime6("elmx_core_task_map5", [fun, a, b, c, d, e])

      {"Task.sequence", [tasks]} ->
        runtime2("elmx_core_task_sequence", [tasks])

      {"Task.onError", [recover, task]} ->
        runtime2("elmx_core_task_on_error", [recover, task])

      {"Task.mapError", [convert, task]} ->
        runtime2("elmx_core_task_map_error", [convert, task])

      {"Task.attempt", [to_msg, task]} ->
        runtime2("elmx_core_task_attempt", [to_msg, task])

      {"Task.andThen", [fun]} ->
        curried("elmx_core_task_and_then", [fun], "__t")

      {"Task.andThen", [fun, task]} ->
        runtime2("elmx_core_task_and_then", [fun, task])

      {"Random.int", [low, high]} ->
        runtime2("elmx_core_random_generator", [low, high])

      {"Random.normalizeSeed", [value]} ->
        runtime2("elmx_core_random_normalize_seed", [value])

      {"Basics.toFloat", [x]} ->
        runtime2("elmx_basics_to_float", [x])

      {"Basics.pi", []} ->
        {:ok, %{op: :float_literal, value: 3.141592653589793}}

      {"Basics.e", []} ->
        {:ok, %{op: :float_literal, value: 2.718281828459045}}

      {"Basics.floor", [x]} ->
        runtime2("elmx_basics_floor", [x])

      {"Basics.ceiling", [x]} ->
        runtime2("elmx_basics_ceiling", [x])

      {"Basics.round", [x]} ->
        runtime2("elmx_basics_round", [x])

      {"Basics.truncate", [x]} ->
        runtime2("elmx_basics_truncate", [x])

      {"Basics.identity", []} ->
        {:ok, %{op: :lambda, args: ["x"], body: %{op: :var, name: "x"}}}

      {"Random.generate", [to_msg, generator]} ->
        {:ok,
         %{
           op: :runtime_call,
           function: "elmx_cmd_random_generate",
           args: [to_msg, generator]
         }}

      {"Elm.Kernel.Random.generate", [to_msg, generator]} ->
        rewrite("Random.generate", [to_msg, generator])

      {"Basics.compare", []} ->
        curried("elmx_basics_compare", [], "__b")

      {"Basics.compare", [a]} ->
        curried("elmx_basics_compare", [a], "__b")

      {"Basics.compare", [a, b]} ->
        runtime2("elmx_basics_compare", [a, b])

      {"Tuple.first", [tuple]} ->
        {:ok, %{op: :tuple_first, arg: tuple}}

      {"Tuple.second", [tuple]} ->
        {:ok, %{op: :tuple_second, arg: tuple}}

      {"Tuple.pair", [left, right]} ->
        {:ok, %{op: :tuple2, left: left, right: right}}

      {"Tuple.mapFirst", [fun, tuple]} ->
        runtime2("elmc_tuple_map_first", [fun, tuple])

      {"Tuple.mapSecond", [fun, tuple]} ->
        runtime2("elmc_tuple_map_second", [fun, tuple])

      {"Tuple.mapBoth", [f, g, tuple]} ->
        runtime3("elmc_tuple_map_both", [f, g, tuple])

      {"Result.fromMaybe", [err, maybe]} ->
        runtime2("elmc_result_from_maybe", [err, maybe])

      {"Result.toMaybe", [result]} ->
        runtime2("elmc_result_to_maybe", [result])

      {"Basics.clamp", [lo, hi, value]} ->
        runtime3("elmx_math_clamp", [lo, hi, value])

      {"Platform.Sub.none", []} ->
        {:ok, %{op: :int_literal, value: 0}}

      {"Time.every", [_interval, _msg]} ->
        {:ok, %{op: :int_literal, value: 1}}

      {"Elm.Kernel.Time.every", [_interval, _msg]} ->
        {:ok, %{op: :int_literal, value: 1}}

      {"Time.now", []} ->
        {:ok, %{op: :runtime_call, function: "elmx_time_now", args: []}}

      {"Time.getZoneName", []} ->
        {:ok, %{op: :runtime_call, function: "elmx_time_get_zone_name", args: []}}

      {"Time.posixToMillis", [posix]} ->
        {:ok, posix}

      {"Time.millisToPosix", [millis]} ->
        {:ok, millis}

      {"Elm.Kernel.Time.nowMillis", []} ->
        {:ok, %{op: :runtime_call, function: "elmx_kernel_time_now_millis", args: []}}

      {"Elm.Kernel.Time.zoneOffsetMinutes", []} ->
        {:ok, %{op: :runtime_call, function: "elmx_kernel_time_zone_offset_minutes", args: []}}

      # Effect-manager router ops from elm/core; elmx library emit stubs them as succeeded tasks.
      {"Elm.Kernel.Platform.sendToApp", []} ->
        platform_send_stub_lambda(2)

      {"Elm.Kernel.Platform.sendToSelf", []} ->
        platform_send_stub_lambda(2)

      {"Elm.Kernel.Platform.sendToApp", [_router]} ->
        platform_send_stub_lambda(1)

      {"Elm.Kernel.Platform.sendToSelf", [_router]} ->
        platform_send_stub_lambda(1)

      {"Elm.Kernel.Platform.sendToApp", [_router, _msg]} ->
        runtime2("elmx_core_task_succeed", [%{op: :int_literal, value: 0}])

      {"Elm.Kernel.Platform.sendToSelf", [_router, _msg]} ->
        runtime2("elmx_core_task_succeed", [%{op: :int_literal, value: 0}])

      {"Platform.sendToApp", []} ->
        platform_send_stub_lambda(2)

      {"Platform.sendToSelf", []} ->
        platform_send_stub_lambda(2)

      {"Platform.sendToApp", [_router]} ->
        platform_send_stub_lambda(1)

      {"Platform.sendToSelf", [_router]} ->
        platform_send_stub_lambda(1)

      {"Platform.sendToApp", [_router, _msg]} ->
        runtime2("elmx_core_task_succeed", [%{op: :int_literal, value: 0}])

      {"Platform.sendToSelf", [_router, _msg]} ->
        runtime2("elmx_core_task_succeed", [%{op: :int_literal, value: 0}])

      {"Elm.Kernel.Platform.batch", []} ->
        {:ok,
         %{
           op: :lambda,
           args: ["__list"],
           body: %{op: :var, name: "__list"}
         }}

      {"Elm.Kernel.Platform.map", []} ->
        {:ok,
         %{
           op: :lambda,
           args: ["__tagger", "__value"],
           body: %{op: :var, name: "__value"}
         }}

      {"Elm.Kernel.Platform.worker", []} ->
        {:ok, %{op: :int_literal, value: 0}}

      {"Elm.Kernel.Scheduler.succeed", []} ->
        {:ok,
         %{
           op: :lambda,
           args: ["__value"],
           body: %{
             op: :runtime_call,
             function: "elmx_core_task_succeed",
             args: [%{op: :var, name: "__value"}]
           }
         }}

      {"Elm.Kernel.Scheduler.succeed", [value]} ->
        runtime2("elmx_core_task_succeed", [value])

      {"Elm.Kernel.Scheduler.fail", []} ->
        {:ok,
         %{
           op: :lambda,
           args: ["__error"],
           body: %{
             op: :runtime_call,
             function: "elmx_core_task_fail",
             args: [%{op: :var, name: "__error"}]
           }
         }}

      {"Elm.Kernel.Scheduler.fail", [error]} ->
        runtime2("elmx_core_task_fail", [error])

      {"Elm.Kernel.Scheduler.andThen", []} ->
        {:ok,
         %{
           op: :lambda,
           args: ["__callback", "__task"],
           body: %{
             op: :runtime_call,
             function: "elmx_core_task_and_then",
             args: [%{op: :var, name: "__callback"}, %{op: :var, name: "__task"}]
           }
         }}

      {"Elm.Kernel.Scheduler.andThen", [callback]} ->
        unary_bound_task("elmx_core_task_and_then", [callback], "__task")

      {"Elm.Kernel.Scheduler.andThen", [callback, task]} ->
        runtime2("elmx_core_task_and_then", [callback, task])

      {"Elm.Kernel.Scheduler.onError", []} ->
        {:ok,
         %{
           op: :lambda,
           args: ["__callback", "__task"],
           body: %{
             op: :runtime_call,
             function: "elmx_core_task_on_error",
             args: [%{op: :var, name: "__callback"}, %{op: :var, name: "__task"}]
           }
         }}

      {"Elm.Kernel.Scheduler.onError", [callback]} ->
        unary_bound_task("elmx_core_task_on_error", [callback], "__task")

      {"Elm.Kernel.Scheduler.onError", [callback, task]} ->
        runtime2("elmx_core_task_on_error", [callback, task])

      {"Elm.Kernel.Scheduler.spawn", []} ->
        {:ok,
         %{
           op: :lambda,
           args: ["__task"],
           body: %{
             op: :runtime_call,
             function: "elmx_core_task_succeed",
             args: [%{op: :int_literal, value: 0}]
           }
         }}

      {"Elm.Kernel.Scheduler.spawn", [_task]} ->
        runtime2("elmx_core_task_succeed", [%{op: :int_literal, value: 0}])

      {"Elm.Kernel.Scheduler.kill", []} ->
        {:ok,
         %{
           op: :lambda,
           args: ["__id"],
           body: %{
             op: :runtime_call,
             function: "elmx_core_task_succeed",
             args: [%{op: :int_literal, value: 0}]
           }
         }}

      {"Elm.Kernel.Scheduler.kill", [_id]} ->
        runtime2("elmx_core_task_succeed", [%{op: :int_literal, value: 0}])

      # Encode builders stay on Kernel paths (not 1:1 with Json.Encode.* APIs).
      {"Elm.Kernel.Json.wrap", []} ->
        {:ok, %{op: :lambda, args: ["__v"], body: %{op: :var, name: "__v"}}}

      {"Elm.Kernel.Json.wrap", [value]} ->
        {:ok, value}

      {"Elm.Kernel.Json.emptyObject", _} ->
        runtime2("elmx_json_encode_object", [%{op: :list_literal, items: []}])

      {"Elm.Kernel.Json.emptyArray", _} ->
        {:ok, %{op: :list_literal, items: []}}

      {"Elm.Kernel.Json.addField", [key, value, obj]} ->
        runtime2("elmx_json_encode_add_field", [key, value, obj])

      {"Elm.Kernel.Json.addField", [key, value]} ->
        curried("elmx_json_encode_add_field", [key, value], "__obj")

      {"Elm.Kernel.Json.addField", [key]} ->
        {:ok,
         %{
           op: :lambda,
           args: ["__value"],
           body: %{
             op: :lambda,
             args: ["__obj"],
             body: %{
               op: :runtime_call,
               function: "elmx_json_encode_add_field",
               args: [key, %{op: :var, name: "__value"}, %{op: :var, name: "__obj"}]
             }
           }
         }}

      {"Elm.Kernel.Json.addEntry", [func, value, arr]} ->
        runtime2("elmx_json_encode_add_entry", [func, value, arr])

      {"Elm.Kernel.Json.addEntry", [func, value]} ->
        curried("elmx_json_encode_add_entry", [func, value], "__arr")

      {"Elm.Kernel.Json.addEntry", [func]} ->
        {:ok,
         %{
           op: :lambda,
           args: ["__value"],
           body: %{
             op: :lambda,
             args: ["__arr"],
             body: %{
               op: :runtime_call,
               function: "elmx_json_encode_add_entry",
               args: [func, %{op: :var, name: "__value"}, %{op: :var, name: "__arr"}]
             }
           }
         }}

      _ ->
        Elmx.Backend.QualifiedPartials.rewrite(target, args)
    end
  end

  defp unary_bound_task(function, fixed_args, param) do
    {:ok,
     %{
       op: :lambda,
       args: [param],
       body: %{
         op: :runtime_call,
         function: function,
         args: fixed_args ++ [%{op: :var, name: param}]
       }
     }}
  end

  defp platform_send_stub_lambda(1) do
    {:ok,
     %{
       op: :lambda,
       args: ["__msg"],
       body: %{
         op: :runtime_call,
         function: "elmx_core_task_succeed",
         args: [%{op: :int_literal, value: 0}]
       }
     }}
  end

  defp platform_send_stub_lambda(2) do
    {:ok,
     %{
       op: :lambda,
       args: ["__router", "__msg"],
       body: %{
         op: :runtime_call,
         function: "elmx_core_task_succeed",
         args: [%{op: :int_literal, value: 0}]
       }
     }}
  end

  # Elm operators often lower as `Elm.Kernel.Basics.*` / `Elm.Kernel.Utils.*` qualified calls.
  # Emit already handles the `__add__` / `__eq__` family via `:call` nodes.
  defp operator_call_rewrite(target, args) when is_binary(target) and is_list(args) do
    case operator_call_name(target) do
      nil -> :error
      name -> {:ok, %{op: :call, name: name, args: args}}
    end
  end

  defp operator_call_name("Basics.add"), do: "__add__"
  defp operator_call_name("Basics.sub"), do: "__sub__"
  defp operator_call_name("Basics.mul"), do: "__mul__"
  defp operator_call_name("Basics.fdiv"), do: "__fdiv__"
  defp operator_call_name("Basics.idiv"), do: "__idiv__"
  defp operator_call_name("Basics.pow"), do: "__pow__"
  defp operator_call_name("Basics.eq"), do: "__eq__"
  defp operator_call_name("Basics.neq"), do: "__neq__"
  defp operator_call_name("Basics.lt"), do: "__lt__"
  defp operator_call_name("Basics.lte"), do: "__lte__"
  defp operator_call_name("Basics.gt"), do: "__gt__"
  defp operator_call_name("Basics.gte"), do: "__gte__"
  defp operator_call_name("Basics.append"), do: "__append__"
  defp operator_call_name("Utils.equal"), do: "__eq__"
  defp operator_call_name("Utils.notEqual"), do: "__neq__"
  defp operator_call_name("Utils.lt"), do: "__lt__"
  defp operator_call_name("Utils.le"), do: "__lte__"
  defp operator_call_name("Utils.gt"), do: "__gt__"
  defp operator_call_name("Utils.ge"), do: "__gte__"
  defp operator_call_name("Utils.append"), do: "__append__"
  defp operator_call_name(_), do: nil

  # Comparisons / append live under Utils in Kernel IR; emit clauses use Basics.*.
  defp denormalize_utils_alias("Utils.compare"), do: "Basics.compare"
  defp denormalize_utils_alias(target), do: target

  defp curried(function, fixed_args, param) do
    {:ok,
     %{
       op: :lambda,
       args: [param],
       body: %{
         op: :runtime_call,
         function: function,
         args: fixed_args ++ [%{op: :var, name: param}]
       }
     }}
  end

  defp runtime2(function, args) do
    {:ok, %{op: :runtime_call, function: function, args: args}}
  end

  defp runtime3(function, args) do
    {:ok, %{op: :runtime_call, function: function, args: args}}
  end

  defp runtime4(function, args) do
    {:ok, %{op: :runtime_call, function: function, args: args}}
  end

  defp runtime5(function, args) do
    {:ok, %{op: :runtime_call, function: function, args: args}}
  end

  defp runtime6(function, args) do
    {:ok, %{op: :runtime_call, function: function, args: args}}
  end

  # `canonical_target/1` maps `List.*` → `Elm.Kernel.List.*`; match clauses use Elm names.
  # Keep `Elm.Kernel.Pebble*`, `Platform`, `Scheduler`, and Json encode-builders as Kernel
  # paths when emit/rewrite matches those qualified strings directly.
  @stdlib_kernel_modules MapSet.new(~w(
    List Random Basics Utils String Bitwise Char Tuple Debug
    Maybe Result Task Dict Set Array JsArray Process
  ))

  # Kernel names ≠ public Json.Decode / Json.Encode APIs (elm/json).
  @kernel_json_to_decode %{
    "decodeString" => "Json.Decode.string",
    "decodeBool" => "Json.Decode.bool",
    "decodeInt" => "Json.Decode.int",
    "decodeFloat" => "Json.Decode.float",
    "decodeList" => "Json.Decode.list",
    "decodeArray" => "Json.Decode.array",
    "decodeNull" => "Json.Decode.null",
    "decodeField" => "Json.Decode.field",
    "decodeIndex" => "Json.Decode.index",
    "decodeKeyValuePairs" => "Json.Decode.keyValuePairs",
    "decodeValue" => "Json.Decode.value",
    "andThen" => "Json.Decode.andThen",
    "fail" => "Json.Decode.fail",
    "succeed" => "Json.Decode.succeed",
    "oneOf" => "Json.Decode.oneOf",
    "map1" => "Json.Decode.map",
    "map2" => "Json.Decode.map2",
    "map3" => "Json.Decode.map3",
    "map4" => "Json.Decode.map4",
    "map5" => "Json.Decode.map5",
    "map6" => "Json.Decode.map6",
    "map7" => "Json.Decode.map7",
    "map8" => "Json.Decode.map8",
    "run" => "Json.Decode.decodeValue",
    "runOnString" => "Json.Decode.decodeString",
    "encode" => "Json.Encode.encode",
    "encodeNull" => "Json.Encode.null"
  }

  defp denormalize_kernel_shorthand("Elm.Kernel." <> rest) do
    case String.split(rest, ".", parts: 2) do
      ["JsArray", name] ->
        "Array." <> name

      ["Json", name] ->
        Map.get(@kernel_json_to_decode, name, "Elm.Kernel.Json." <> name)

      [mod, name] ->
        if MapSet.member?(@stdlib_kernel_modules, mod) do
          mod <> "." <> name
        else
          "Elm.Kernel." <> rest
        end

      _ ->
        "Elm.Kernel." <> rest
    end
  end

  defp denormalize_kernel_shorthand(target), do: target
end
