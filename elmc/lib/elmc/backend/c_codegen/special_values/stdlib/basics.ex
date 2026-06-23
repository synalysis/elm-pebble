defmodule Elmc.Backend.CCodegen.SpecialValues.Stdlib.Basics do
  @moduledoc false

  alias Elmc.Backend.CCodegen.SpecialValues.Helpers
  alias Elmc.Backend.CCodegen.Types

  @behaviour Elmc.Backend.CCodegen.SpecialValues.Handler

  @impl true
  @spec special_value_from_target(String.t(), Types.special_value_args()) ::
          Types.special_value_result()
  def special_value_from_target("Basics.max", [left, right]),
    do: %{op: :runtime_call, function: "elmc_basics_max", args: [left, right]}

  def special_value_from_target("Basics.min", [left, right]),
    do: %{op: :runtime_call, function: "elmc_basics_min", args: [left, right]}

  def special_value_from_target("Basics.clamp", [low, high, value]),
    do: %{op: :runtime_call, function: "elmc_basics_clamp", args: [low, high, value]}

  def special_value_from_target("Basics.modBy", [base, value]),
    do: %{op: :runtime_call, function: "elmc_basics_mod_by", args: [base, value]}

  def special_value_from_target("Basics.remainderBy", [base, value]),
    do: %{op: :runtime_call, function: "elmc_basics_remainder_by", args: [base, value]}

  def special_value_from_target("Bitwise.and", [left, right]),
    do: %{op: :runtime_call, function: "elmc_bitwise_and", args: [left, right]}

  def special_value_from_target("Bitwise.or", [left, right]),
    do: %{op: :runtime_call, function: "elmc_bitwise_or", args: [left, right]}

  def special_value_from_target("Bitwise.xor", [left, right]),
    do: %{op: :runtime_call, function: "elmc_bitwise_xor", args: [left, right]}

  def special_value_from_target("Bitwise.complement", [value]),
    do: %{op: :runtime_call, function: "elmc_bitwise_complement", args: [value]}

  def special_value_from_target("Bitwise.shiftLeftBy", [bits, value]),
    do: %{op: :runtime_call, function: "elmc_bitwise_shift_left_by", args: [bits, value]}

  def special_value_from_target("Bitwise.shiftRightBy", [bits, value]),
    do: %{op: :runtime_call, function: "elmc_bitwise_shift_right_by", args: [bits, value]}

  def special_value_from_target("Bitwise.shiftRightZfBy", [bits, value]),
    do: %{op: :runtime_call, function: "elmc_bitwise_shift_right_zf_by", args: [bits, value]}

  def special_value_from_target("Tuple.pair", [left, right]),
    do: %{op: :tuple2, left: left, right: right}

  def special_value_from_target("Tuple.pair", []),
    do: %{
      op: :lambda,
      args: ["__a", "__b"],
      body: %{op: :tuple2, left: %{op: :var, name: "__a"}, right: %{op: :var, name: "__b"}}
    }

  def special_value_from_target("Tuple.pair", [left]),
    do: %{
      op: :lambda,
      args: ["__b"],
      body: %{op: :tuple2, left: left, right: %{op: :var, name: "__b"}}
    }

  def special_value_from_target("Basics.identity", []),
    do: %{op: :lambda, args: ["__x"], body: %{op: :var, name: "__x"}}

  def special_value_from_target("Basics.always", []),
    do: %{op: :lambda, args: ["__a", "__b"], body: %{op: :var, name: "__a"}}

  def special_value_from_target("Basics.always", [x]),
    do: %{op: :lambda, args: ["__ignored"], body: x}

  def special_value_from_target("Basics.negate", []),
    do: %{
      op: :lambda,
      args: ["__x"],
      body: %{op: :runtime_call, function: "elmc_basics_negate", args: [%{op: :var, name: "__x"}]}
    }

  def special_value_from_target("Basics.not", []),
    do: %{
      op: :lambda,
      args: ["__x"],
      body: %{op: :runtime_call, function: "elmc_basics_not", args: [%{op: :var, name: "__x"}]}
    }

  def special_value_from_target("Basics.abs", []),
    do: %{
      op: :lambda,
      args: ["__x"],
      body: %{op: :runtime_call, function: "elmc_basics_abs", args: [%{op: :var, name: "__x"}]}
    }

  def special_value_from_target("Basics.toFloat", []),
    do: %{
      op: :lambda,
      args: ["__x"],
      body: %{
        op: :runtime_call,
        function: "elmc_basics_to_float",
        args: [%{op: :var, name: "__x"}]
      }
    }

  def special_value_from_target("Basics.sqrt", []), do: Helpers.unary_runtime_lambda("elmc_basics_sqrt")

  def special_value_from_target("Basics.logBase", []),
    do: Helpers.binary_runtime_lambda("elmc_basics_log_base")

  def special_value_from_target("Basics.logBase", [base]),
    do: Helpers.bound_binary_runtime_lambda("elmc_basics_log_base", base)

  def special_value_from_target("Basics.cos", []), do: Helpers.unary_runtime_lambda("elmc_basics_cos")
  def special_value_from_target("Basics.sin", []), do: Helpers.unary_runtime_lambda("elmc_basics_sin")
  def special_value_from_target("Basics.tan", []), do: Helpers.unary_runtime_lambda("elmc_basics_tan")
  def special_value_from_target("Basics.acos", []), do: Helpers.unary_runtime_lambda("elmc_basics_acos")
  def special_value_from_target("Basics.asin", []), do: Helpers.unary_runtime_lambda("elmc_basics_asin")
  def special_value_from_target("Basics.atan", []), do: Helpers.unary_runtime_lambda("elmc_basics_atan")

  def special_value_from_target("Basics.atan2", []),
    do: Helpers.binary_runtime_lambda("elmc_basics_atan2")

  def special_value_from_target("Basics.atan2", [y]),
    do: Helpers.bound_binary_runtime_lambda("elmc_basics_atan2", y)

  def special_value_from_target("Basics.degrees", []),
    do: Helpers.unary_runtime_lambda("elmc_basics_degrees")

  def special_value_from_target("Basics.radians", []),
    do: Helpers.unary_runtime_lambda("elmc_basics_radians")

  def special_value_from_target("Basics.turns", []),
    do: Helpers.unary_runtime_lambda("elmc_basics_turns")

  def special_value_from_target("Basics.fromPolar", []),
    do: Helpers.unary_runtime_lambda("elmc_basics_from_polar")

  def special_value_from_target("Basics.toPolar", []),
    do: Helpers.unary_runtime_lambda("elmc_basics_to_polar")

  def special_value_from_target("Basics.isNaN", []),
    do: Helpers.unary_runtime_lambda("elmc_basics_is_nan")

  def special_value_from_target("Basics.isInfinite", []),
    do: Helpers.unary_runtime_lambda("elmc_basics_is_infinite")

  def special_value_from_target("Basics.round", []),
    do: %{
      op: :lambda,
      args: ["__x"],
      body: %{op: :runtime_call, function: "elmc_basics_round", args: [%{op: :var, name: "__x"}]}
    }

  def special_value_from_target("Basics.floor", []),
    do: %{
      op: :lambda,
      args: ["__x"],
      body: %{op: :runtime_call, function: "elmc_basics_floor", args: [%{op: :var, name: "__x"}]}
    }

  def special_value_from_target("Basics.ceiling", []),
    do: %{
      op: :lambda,
      args: ["__x"],
      body: %{
        op: :runtime_call,
        function: "elmc_basics_ceiling",
        args: [%{op: :var, name: "__x"}]
      }
    }

  def special_value_from_target("Basics.max", []), do: Helpers.binary_runtime_lambda("elmc_basics_max")

  def special_value_from_target("Basics.max", [left]),
    do: Helpers.bound_binary_runtime_lambda("elmc_basics_max", left)

  def special_value_from_target("Basics.min", []), do: Helpers.binary_runtime_lambda("elmc_basics_min")

  def special_value_from_target("Basics.min", [left]),
    do: Helpers.bound_binary_runtime_lambda("elmc_basics_min", left)

  def special_value_from_target("Basics.clamp", []),
    do: Helpers.ternary_runtime_lambda("elmc_basics_clamp")

  def special_value_from_target("Basics.clamp", [low]),
    do: Helpers.bound_ternary_runtime_lambda("elmc_basics_clamp", low)

  def special_value_from_target("Basics.clamp", [low, high]),
    do: Helpers.bound_ternary_runtime_lambda("elmc_basics_clamp", low, high)

  def special_value_from_target("Basics.modBy", []),
    do: Helpers.binary_runtime_lambda("elmc_basics_mod_by")

  def special_value_from_target("Basics.modBy", [base]),
    do: Helpers.bound_binary_runtime_lambda("elmc_basics_mod_by", base)

  def special_value_from_target("Basics.remainderBy", []),
    do: Helpers.binary_runtime_lambda("elmc_basics_remainder_by")

  def special_value_from_target("Basics.remainderBy", [base]),
    do: Helpers.bound_binary_runtime_lambda("elmc_basics_remainder_by", base)

  def special_value_from_target("Basics.xor", []), do: Helpers.binary_runtime_lambda("elmc_basics_xor")

  def special_value_from_target("Basics.xor", [a]),
    do: Helpers.bound_binary_runtime_lambda("elmc_basics_xor", a)

  def special_value_from_target("Basics.compare", []),
    do: Helpers.binary_runtime_lambda("elmc_basics_compare")

  def special_value_from_target("Basics.compare", [a]),
    do: Helpers.bound_binary_runtime_lambda("elmc_basics_compare", a)

  def special_value_from_target("Basics.truncate", []),
    do: %{
      op: :lambda,
      args: ["__x"],
      body: %{
        op: :runtime_call,
        function: "elmc_basics_truncate",
        args: [%{op: :var, name: "__x"}]
      }
    }

  def special_value_from_target("Tuple.first", [t]),
    do: %{op: :runtime_call, function: "elmc_tuple_first", args: [t]}

  def special_value_from_target("Tuple.second", [t]),
    do: %{op: :runtime_call, function: "elmc_tuple_second", args: [t]}

  def special_value_from_target("Tuple.first", []),
    do: Helpers.runtime_fn_lambda("elmc_tuple_first", ["__t"])

  def special_value_from_target("Tuple.second", []),
    do: Helpers.runtime_fn_lambda("elmc_tuple_second", ["__t"])

  def special_value_from_target("Tuple.mapFirst", [f, t]),
    do: %{op: :runtime_call, function: "elmc_tuple_map_first", args: [f, t]}

  def special_value_from_target("Tuple.mapSecond", [f, t]),
    do: %{op: :runtime_call, function: "elmc_tuple_map_second", args: [f, t]}

  def special_value_from_target("Tuple.mapBoth", [f, g, t]),
    do: %{op: :runtime_call, function: "elmc_tuple_map_both", args: [f, g, t]}

  # --- elm/core: Basics (extended) ---
  def special_value_from_target("Basics.identity", [x]), do: x

  def special_value_from_target("Basics.always", [x, _y]), do: x

  def special_value_from_target("Basics.not", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_not", args: [x]}

  def special_value_from_target("Basics.negate", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_negate", args: [x]}

  def special_value_from_target("Basics.abs", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_abs", args: [x]}

  def special_value_from_target("Basics.toFloat", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_to_float", args: [x]}

  def special_value_from_target("Basics.e", _args),
    do: %{op: :float_literal, value: 2.718281828459045}

  def special_value_from_target("Basics.pi", _args),
    do: %{op: :float_literal, value: 3.141592653589793}

  def special_value_from_target("Basics.sqrt", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_sqrt", args: [x]}

  def special_value_from_target("Basics.logBase", [base, x]),
    do: %{op: :runtime_call, function: "elmc_basics_log_base", args: [base, x]}

  def special_value_from_target("Basics.sin", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_sin", args: [x]}

  def special_value_from_target("Basics.cos", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_cos", args: [x]}

  def special_value_from_target("Basics.tan", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_tan", args: [x]}

  def special_value_from_target("Basics.acos", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_acos", args: [x]}

  def special_value_from_target("Basics.asin", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_asin", args: [x]}

  def special_value_from_target("Basics.atan", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_atan", args: [x]}

  def special_value_from_target("Basics.atan2", [y, x]),
    do: %{op: :runtime_call, function: "elmc_basics_atan2", args: [y, x]}

  def special_value_from_target("Basics.degrees", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_degrees", args: [x]}

  def special_value_from_target("Basics.radians", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_radians", args: [x]}

  def special_value_from_target("Basics.turns", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_turns", args: [x]}

  def special_value_from_target("Basics.fromPolar", [polar]),
    do: %{op: :runtime_call, function: "elmc_basics_from_polar", args: [polar]}

  def special_value_from_target("Basics.toPolar", [point]),
    do: %{op: :runtime_call, function: "elmc_basics_to_polar", args: [point]}

  def special_value_from_target("Basics.isNaN", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_is_nan", args: [x]}

  def special_value_from_target("Basics.isInfinite", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_is_infinite", args: [x]}

  def special_value_from_target("Basics.round", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_round", args: [x]}

  def special_value_from_target("Basics.floor", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_floor", args: [x]}

  def special_value_from_target("Basics.ceiling", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_ceiling", args: [x]}

  def special_value_from_target("Basics.truncate", [x]),
    do: %{op: :runtime_call, function: "elmc_basics_truncate", args: [x]}

  def special_value_from_target("Basics.xor", [a, b]),
    do: %{op: :runtime_call, function: "elmc_basics_xor", args: [a, b]}

  def special_value_from_target("Basics.compare", [a, b]),
    do: %{op: :runtime_call, function: "elmc_basics_compare", args: [a, b]}

  # --- elm/core: Char (extended) ---

  def special_value_from_target(_target, _args), do: nil
end
