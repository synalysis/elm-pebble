defmodule Elmx.Backend.QualifiedRewrite do
  @moduledoc """
  Rewrites `qualified_call` IR to expression nodes (mirrors `elmc` `special_value_from_target/2`).
  """

  alias Elmx.Types

  @spec rewrite(String.t(), list()) :: Types.rewrite_result()
  def rewrite(target, args) when is_binary(target) and is_list(args) do
    target =
      target
      |> Elmx.Runtime.Pebble.SpecialValues.canonical_target()
      |> denormalize_kernel_shorthand()

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

      _ ->
        Elmx.Backend.QualifiedPartials.rewrite(target, args)
    end
  end

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
  defp denormalize_kernel_shorthand("Elm.Kernel.List." <> rest), do: "List." <> rest
  defp denormalize_kernel_shorthand("Elm.Kernel.Random." <> rest), do: "Random." <> rest
  defp denormalize_kernel_shorthand(target), do: target
end
