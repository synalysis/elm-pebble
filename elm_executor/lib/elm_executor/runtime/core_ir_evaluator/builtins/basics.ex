defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Basics do
  @moduledoc false

  @spec eval(String.t(), term(), map()) :: {:ok, term()} | :no_builtin | {:error, term()}
  def eval("pi", [], _ops), do: {:ok, :math.pi()}
  def eval("e", [], _ops), do: {:ok, :math.exp(1.0)}
  def eval("lt", [], _ops), do: {:ok, %{"ctor" => "LT", "args" => []}}
  def eval("eq", [], _ops), do: {:ok, %{"ctor" => "EQ", "args" => []}}
  def eval("gt", [], _ops), do: {:ok, %{"ctor" => "GT", "args" => []}}
  def eval("map2", [a, b, c], ops), do: ops.map2_dispatch.(a, b, c)
  def eval("identity", [value], _ops), do: {:ok, value}
  def eval("identity", [], _ops), do: {:ok, {:builtin_partial, "identity", []}}
  def eval("always", [], _ops), do: {:ok, {:builtin_partial, "always", []}}
  def eval("always", [value], _ops), do: {:ok, {:builtin_partial, "always", [value]}}
  def eval("always", [value, _ignored], _ops), do: {:ok, value}
  def eval("not", [], _ops), do: {:ok, {:builtin_partial, "not", []}}
  def eval("not", [value], _ops) when is_boolean(value), do: {:ok, !value}
  def eval("xor", [], _ops), do: {:ok, {:builtin_partial, "xor", []}}
  def eval("xor", [a], _ops) when is_boolean(a), do: {:ok, {:builtin_partial, "xor", [a]}}
  def eval("xor", [a, b], _ops) when is_boolean(a) and is_boolean(b), do: {:ok, a != b}
  def eval("max", [], _ops), do: {:ok, {:builtin_partial, "max", []}}
  def eval("max", [a], _ops), do: {:ok, {:builtin_partial, "max", [a]}}
  def eval("max", [a, b], _ops), do: {:ok, if(a >= b, do: a, else: b)}
  def eval("min", [], _ops), do: {:ok, {:builtin_partial, "min", []}}
  def eval("min", [a], _ops), do: {:ok, {:builtin_partial, "min", [a]}}
  def eval("min", [a, b], _ops), do: {:ok, if(a <= b, do: a, else: b)}
  def eval("clamp", [], _ops), do: {:ok, {:builtin_partial, "clamp", []}}
  def eval("clamp", [low], _ops), do: {:ok, {:builtin_partial, "clamp", [low]}}
  def eval("clamp", [low, high], _ops), do: {:ok, {:builtin_partial, "clamp", [low, high]}}

  def eval("clamp", [low, high, value], _ops) do
    {:ok, value |> max(low) |> min(high)}
  end

  def eval("compare", [], _ops), do: {:ok, {:builtin_partial, "compare", []}}
  def eval("compare", [a], _ops), do: {:ok, {:builtin_partial, "compare", [a]}}
  def eval("compare", [a, b], ops), do: ops.compare.(a, b)

  def eval("modby", [], _ops), do: {:ok, {:builtin_partial, "modBy", []}}

  def eval("modby", [by, value], _ops) when is_integer(by) and by != 0 and is_integer(value),
    do: {:ok, Integer.mod(value, by)}

  def eval("modby", [by], _ops) when is_integer(by) and by != 0,
    do: {:ok, {:builtin_partial, "modBy", [by]}}

  def eval("remainderby", [], _ops), do: {:ok, {:builtin_partial, "remainderBy", []}}

  def eval("remainderby", [by, value], _ops) when is_integer(by) and by != 0 and is_integer(value),
    do: {:ok, rem(value, by)}

  def eval("remainderby", [by], _ops) when is_integer(by) and by != 0,
    do: {:ok, {:builtin_partial, "remainderBy", [by]}}

  def eval("negate", [], _ops), do: {:ok, {:builtin_partial, "negate", []}}
  def eval("negate", [value], _ops) when is_number(value), do: {:ok, -value}
  def eval("abs", [], _ops), do: {:ok, {:builtin_partial, "abs", []}}
  def eval("abs", [value], _ops) when is_number(value), do: {:ok, abs(value)}
  def eval("tofloat", [], _ops), do: {:ok, {:builtin_partial, "toFloat", []}}
  def eval("tofloat", [value], _ops) when is_integer(value), do: {:ok, value * 1.0}
  def eval("tofloat", [value], _ops) when is_float(value), do: {:ok, value}
  def eval("round", [], _ops), do: {:ok, {:builtin_partial, "round", []}}
  def eval("round", [value], _ops) when is_number(value), do: {:ok, round(value)}
  def eval("floor", [], _ops), do: {:ok, {:builtin_partial, "floor", []}}
  def eval("floor", [value], _ops) when is_number(value), do: {:ok, floor(value)}
  def eval("ceiling", [], _ops), do: {:ok, {:builtin_partial, "ceiling", []}}
  def eval("ceiling", [value], _ops) when is_number(value), do: {:ok, ceil(value)}
  def eval("truncate", [], _ops), do: {:ok, {:builtin_partial, "truncate", []}}
  def eval("truncate", [value], _ops) when is_number(value), do: {:ok, trunc(value)}
  def eval("sqrt", [], _ops), do: {:ok, {:builtin_partial, "sqrt", []}}
  def eval("sqrt", [value], _ops) when is_number(value), do: safe_math_unary(&:math.sqrt/1, value)
  def eval("cos", [], _ops), do: {:ok, {:builtin_partial, "cos", []}}
  def eval("cos", [value], _ops) when is_number(value), do: safe_math_unary(&:math.cos/1, value)
  def eval("sin", [], _ops), do: {:ok, {:builtin_partial, "sin", []}}
  def eval("sin", [value], _ops) when is_number(value), do: safe_math_unary(&:math.sin/1, value)
  def eval("tan", [], _ops), do: {:ok, {:builtin_partial, "tan", []}}
  def eval("tan", [value], _ops) when is_number(value), do: safe_math_unary(&:math.tan/1, value)
  def eval("acos", [], _ops), do: {:ok, {:builtin_partial, "acos", []}}
  def eval("acos", [value], _ops) when is_number(value), do: safe_math_unary(&:math.acos/1, value)
  def eval("asin", [], _ops), do: {:ok, {:builtin_partial, "asin", []}}
  def eval("asin", [value], _ops) when is_number(value), do: safe_math_unary(&:math.asin/1, value)
  def eval("atan", [], _ops), do: {:ok, {:builtin_partial, "atan", []}}
  def eval("atan", [value], _ops) when is_number(value), do: safe_math_unary(&:math.atan/1, value)
  def eval("atan2", [], _ops), do: {:ok, {:builtin_partial, "atan2", []}}
  def eval("atan2", [y], _ops) when is_number(y), do: {:ok, {:builtin_partial, "atan2", [y]}}

  def eval("atan2", [y, x], _ops) when is_number(y) and is_number(x),
    do: safe_math_binary(&:math.atan2/2, y, x)

  def eval("logbase", [], _ops), do: {:ok, {:builtin_partial, "logBase", []}}
  def eval("logbase", [base], _ops) when is_number(base), do: {:ok, {:builtin_partial, "logBase", [base]}}

  def eval("logbase", [base, n], _ops) when is_number(base) and is_number(n),
    do: safe_log_base(base, n)

  def eval("degrees", [], _ops), do: {:ok, {:builtin_partial, "degrees", []}}
  def eval("degrees", [value], _ops) when is_number(value), do: {:ok, value * :math.pi() / 180.0}
  def eval("radians", [], _ops), do: {:ok, {:builtin_partial, "radians", []}}
  def eval("radians", [value], _ops) when is_number(value), do: {:ok, value}
  def eval("turns", [], _ops), do: {:ok, {:builtin_partial, "turns", []}}
  def eval("turns", [value], _ops) when is_number(value), do: {:ok, value * 2.0 * :math.pi()}
  def eval("frompolar", [], _ops), do: {:ok, {:builtin_partial, "fromPolar", []}}

  def eval("frompolar", [{radius, theta}], _ops) when is_number(radius) and is_number(theta),
    do: {:ok, {radius * :math.cos(theta), radius * :math.sin(theta)}}

  def eval("topolar", [], _ops), do: {:ok, {:builtin_partial, "toPolar", []}}

  def eval("topolar", [{x, y}], _ops) when is_number(x) and is_number(y),
    do: {:ok, {:math.sqrt(x * x + y * y), :math.atan2(y, x)}}

  def eval("isnan", [], _ops), do: {:ok, {:builtin_partial, "isNaN", []}}

  def eval("isnan", [value], _ops),
    do: {:ok, value == :nan or (is_float(value) and value != value)}

  def eval("isinfinite", [], _ops), do: {:ok, {:builtin_partial, "isInfinite", []}}
  def eval("isinfinite", [value], _ops), do: {:ok, infinite?(value)}
  def eval(_function_name, _values, _ops), do: :no_builtin

  defp safe_math_unary(fun, value) when is_function(fun, 1) do
    try do
      {:ok, fun.(value)}
    rescue
      ArithmeticError -> {:ok, :nan}
    end
  end

  defp safe_math_binary(fun, left, right) when is_function(fun, 2) do
    try do
      {:ok, fun.(left, right)}
    rescue
      ArithmeticError -> {:ok, :nan}
    end
  end

  defp safe_log_base(base, n) do
    try do
      {:ok, :math.log(n) / :math.log(base)}
    rescue
      ArithmeticError -> {:ok, :nan}
    end
  end

  defp infinite?(:nan), do: false
  defp infinite?(:infinity), do: true
  defp infinite?(:neg_infinity), do: true

  defp infinite?(value) when is_float(value),
    do:
      String.contains?(:erlang.float_to_binary(value, [:compact]) |> String.downcase(), "inf")

  defp infinite?(_), do: false
end
