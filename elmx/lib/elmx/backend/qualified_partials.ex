defmodule Elmx.Backend.QualifiedPartials do
  @moduledoc """
  Partial-application rewrites for `qualified_call` (mirrors `elmc` `c_codegen` zero/low-arity clauses).
  """

  @spec rewrite(String.t(), list()) :: {:ok, map()} | :error
  def rewrite(target, args) when is_binary(target) and is_list(args) do
    case {target, args} do
      # --- List (0-arg references) ---
      {"List.head", []} -> unary("elmc_list_head", "__l")
      {"List.tail", []} -> unary("elmc_list_tail", "__l")
      {"List.reverse", []} -> unary("elmc_list_reverse", "__l")
      {"List.length", []} -> unary("elmc_list_length", "__l")
      {"List.isEmpty", []} -> unary("elmc_list_is_empty", "__l")
      {"List.sum", []} -> unary("elmc_list_sum", "__l")
      {"List.product", []} -> unary("elmc_list_product", "__l")
      {"List.maximum", []} -> unary("elmc_list_maximum", "__l")
      {"List.minimum", []} -> unary("elmc_list_minimum", "__l")
      {"List.sort", []} -> unary("elmc_list_sort", "__l")
      {"List.concat", []} -> unary("elmc_list_concat", "__l")

      # --- Result ---
      {"Result.toMaybe", []} -> unary("elmc_result_to_maybe", "__r")

      # --- String (0-arg references) ---
      {"String.fromInt", []} -> unary("elmc_string_from_int", "__n")
      {"String.fromFloat", []} -> unary("elmc_string_from_float", "__f")
      {"String.toInt", []} -> unary("elmc_string_to_int", "__s")
      {"String.toFloat", []} -> unary("elmc_string_to_float", "__s")
      {"String.isEmpty", []} -> unary("elmc_string_is_empty", "__s")
      {"String.length", []} -> unary("elmc_string_length_val", "__s")
      {"String.reverse", []} -> unary("elmc_string_reverse", "__s")
      {"String.toUpper", []} -> unary("elmc_string_to_upper", "__s")
      {"String.toLower", []} -> unary("elmc_string_to_lower", "__s")
      {"String.trim", []} -> unary("elmc_string_trim", "__s")
      {"String.words", []} -> unary("elmc_string_words", "__s")
      {"String.lines", []} -> unary("elmc_string_lines", "__s")

      # --- Char ---
      {"Char.toCode", []} -> unary("elmc_char_to_code", "__ch")
      {"Char.fromCode", []} -> unary("elmc_new_char", "__c")

      # --- Debug ---
      {"Debug.toString", []} -> unary("elmc_debug_to_string", "__v")
      {"Debug.log", [label]} -> unary_bound("elmc_debug_log", [label], "__v")

      # --- Basics ---
      {"Basics.identity", []} ->
        {:ok, %{op: :lambda, args: ["__x"], body: %{op: :var, name: "__x"}}}

      {"Basics.always", []} ->
        {:ok, %{op: :lambda, args: ["__a", "__b"], body: %{op: :var, name: "__a"}}}

      {"Basics.always", [x]} ->
        {:ok, %{op: :lambda, args: ["__ignored"], body: x}}

      {"Basics.negate", []} -> unary("elmc_basics_negate", "__x")
      {"Basics.not", []} -> unary("elmc_basics_not", "__x")
      {"Basics.abs", []} -> unary("elmc_basics_abs", "__x")
      {"Basics.toFloat", []} -> unary("elmc_basics_to_float", "__x")
      {"Basics.round", []} -> unary("elmc_basics_round", "__x")
      {"Basics.floor", []} -> unary("elmc_basics_floor", "__x")
      {"Basics.ceiling", []} -> unary("elmc_basics_ceiling", "__x")
      {"Basics.truncate", []} -> unary("elmc_basics_truncate", "__x")

      {"Basics.sqrt", []} -> unary("elmc_basics_sqrt", "__x")
      {"Basics.sin", []} -> unary("elmc_basics_sin", "__x")
      {"Basics.cos", []} -> unary("elmc_basics_cos", "__x")
      {"Basics.tan", []} -> unary("elmc_basics_tan", "__x")
      {"Basics.asin", []} -> unary("elmc_basics_asin", "__x")
      {"Basics.acos", []} -> unary("elmc_basics_acos", "__x")
      {"Basics.atan", []} -> unary("elmc_basics_atan", "__x")
      {"Basics.degrees", []} -> unary("elmc_basics_degrees", "__x")
      {"Basics.radians", []} -> unary("elmc_basics_radians", "__x")
      {"Basics.turns", []} -> unary("elmc_basics_turns", "__x")
      {"Basics.fromPolar", []} -> unary("elmc_basics_from_polar", "__x")
      {"Basics.toPolar", []} -> unary("elmc_basics_to_polar", "__x")
      {"Basics.isNaN", []} -> unary("elmc_basics_is_nan", "__x")
      {"Basics.isInfinite", []} -> unary("elmc_basics_is_infinite", "__x")

      {"Basics.logBase", []} -> binary("elmc_basics_log_base", "__b", "__x")
      {"Basics.logBase", [base]} -> binary_bound("elmc_basics_log_base", [base], "__x")

      {"Basics.atan2", []} -> binary("elmc_basics_atan2", "__y", "__x")
      {"Basics.atan2", [y]} -> binary_bound("elmc_basics_atan2", [y], "__x")

      {"Basics.max", []} -> binary("elmc_basics_max", "__a", "__b")
      {"Basics.max", [left]} -> binary_bound("elmc_basics_max", [left], "__b")
      {"Basics.min", []} -> binary("elmc_basics_min", "__a", "__b")
      {"Basics.min", [left]} -> binary_bound("elmc_basics_min", [left], "__b")

      {"Basics.clamp", []} -> ternary("elmc_basics_clamp", "__lo", "__hi", "__v")
      {"Basics.clamp", [low]} -> ternary_bound("elmc_basics_clamp", [low], ["__hi", "__v"])
      {"Basics.clamp", [low, high]} -> ternary_bound("elmc_basics_clamp", [low, high], ["__v"])

      {"Basics.modBy", []} -> binary("elmc_basics_mod_by", "__base", "__v")
      {"Basics.modBy", [base]} -> binary_bound("elmc_basics_mod_by", [base], "__v")

      {"Basics.remainderBy", []} -> binary("elmc_basics_remainder_by", "__base", "__v")
      {"Basics.remainderBy", [base]} -> binary_bound("elmc_basics_remainder_by", [base], "__v")

      {"Basics.xor", []} -> binary("elmc_basics_xor", "__a", "__b")
      {"Basics.xor", [a]} -> binary_bound("elmc_basics_xor", [a], "__b")

      {"Basics.compare", [a]} -> binary_bound("elmc_basics_compare", [a], "__b")

      {"Task.map", [fun]} -> unary_bound("elmx_core_task_map", [fun], "__t")

      {"Task.map2", [fun]} ->
        {:ok,
         %{
           op: :lambda,
           args: ["__a", "__b"],
           body: %{
             op: :runtime_call,
             function: "elmx_core_task_map2",
             args: [fun, %{op: :var, name: "__a"}, %{op: :var, name: "__b"}]
           }
         }}

      {"Task.map2", [fun, a]} ->
        ternary_bound("elmx_core_task_map2", [fun, a], ["__b"])

      {"Task.andThen", [fun]} -> unary_bound("elmx_core_task_and_then", [fun], "__t")

      # --- Tuple (pair uses tuple2 IR, not a runtime call) ---
      {"Tuple.pair", []} ->
        {:ok,
         %{
           op: :lambda,
           args: ["__a", "__b"],
           body: %{
             op: :tuple2,
             left: %{op: :var, name: "__a"},
             right: %{op: :var, name: "__b"}
           }
         }}

      {"Tuple.pair", [left]} ->
        {:ok,
         %{
           op: :lambda,
           args: ["__b"],
           body: %{op: :tuple2, left: left, right: %{op: :var, name: "__b"}}
         }}

      _ ->
        :error
    end
  end

  defp unary(function, param) do
    {:ok,
     %{
       op: :lambda,
       args: [param],
       body: %{
         op: :runtime_call,
         function: function,
         args: [%{op: :var, name: param}]
       }
     }}
  end

  defp unary_bound(function, fixed, param) do
    {:ok,
     %{
       op: :lambda,
       args: [param],
       body: %{
         op: :runtime_call,
         function: function,
         args: fixed ++ [%{op: :var, name: param}]
       }
     }}
  end

  defp binary(function, p1, p2) do
    {:ok,
     %{
       op: :lambda,
       args: [p1, p2],
       body: %{
         op: :runtime_call,
         function: function,
         args: [%{op: :var, name: p1}, %{op: :var, name: p2}]
       }
     }}
  end

  defp binary_bound(function, fixed, param) do
    {:ok,
     %{
       op: :lambda,
       args: [param],
       body: %{
         op: :runtime_call,
         function: function,
         args: fixed ++ [%{op: :var, name: param}]
       }
     }}
  end

  defp ternary(function, p1, p2, p3) do
    {:ok,
     %{
       op: :lambda,
       args: [p1, p2, p3],
       body: %{
         op: :runtime_call,
         function: function,
         args: [
           %{op: :var, name: p1},
           %{op: :var, name: p2},
           %{op: :var, name: p3}
         ]
       }
     }}
  end

  defp ternary_bound(function, fixed, params) do
    {:ok,
     %{
       op: :lambda,
       args: params,
       body: %{
         op: :runtime_call,
         function: function,
         args: fixed ++ Enum.map(params, &%{op: :var, name: &1})
       }
     }}
  end
end
