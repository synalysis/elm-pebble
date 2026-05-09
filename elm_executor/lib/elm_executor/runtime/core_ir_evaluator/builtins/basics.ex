defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Basics do
  @moduledoc false

  @spec eval(String.t(), term(), map()) :: {:ok, term()} | :no_builtin | {:error, term()}
  def eval("map2", [a, b, c], ops), do: ops.map2_dispatch.(a, b, c)
  def eval("identity", [value], _ops), do: {:ok, value}
  def eval("always", [value], _ops), do: {:ok, {:builtin_partial, "always", [value]}}
  def eval("always", [value, _ignored], _ops), do: {:ok, value}
  def eval("not", [value], _ops) when is_boolean(value), do: {:ok, !value}
  def eval("xor", [a, b], _ops) when is_boolean(a) and is_boolean(b), do: {:ok, a != b}
  def eval("max", [a, b], _ops), do: {:ok, if(a >= b, do: a, else: b)}
  def eval("min", [a, b], _ops), do: {:ok, if(a <= b, do: a, else: b)}

  def eval("clamp", [low, high, value], _ops) do
    {:ok, value |> max(low) |> min(high)}
  end

  def eval("compare", [a, b], ops), do: ops.compare.(a, b)

  def eval("modby", [by, value], _ops) when is_integer(by) and by > 0 and is_integer(value),
    do: {:ok, Integer.mod(value, by)}

  def eval("modby", [by], _ops) when is_integer(by) and by > 0,
    do: {:ok, {:builtin_partial, "modBy", [by]}}

  def eval("remainderby", [by, value], _ops) when is_integer(by) and by > 0 and is_integer(value),
    do: {:ok, rem(value, by)}

  def eval("remainderby", [by], _ops) when is_integer(by) and by > 0,
    do: {:ok, {:builtin_partial, "remainderBy", [by]}}

  def eval("negate", [value], _ops) when is_number(value), do: {:ok, -value}
  def eval("abs", [value], _ops) when is_number(value), do: {:ok, abs(value)}
  def eval("tofloat", [value], _ops) when is_integer(value), do: {:ok, value * 1.0}
  def eval("tofloat", [value], _ops) when is_float(value), do: {:ok, value}
  def eval("round", [value], _ops) when is_number(value), do: {:ok, round(value)}
  def eval("floor", [value], _ops) when is_number(value), do: {:ok, floor(value)}
  def eval("ceiling", [value], _ops) when is_number(value), do: {:ok, ceil(value)}
  def eval("truncate", [value], _ops) when is_number(value), do: {:ok, trunc(value)}
  def eval("sqrt", [value], _ops) when is_number(value), do: safe_math_unary(&:math.sqrt/1, value)
  def eval("cos", [value], _ops) when is_number(value), do: safe_math_unary(&:math.cos/1, value)
  def eval("sin", [value], _ops) when is_number(value), do: safe_math_unary(&:math.sin/1, value)
  def eval("tan", [value], _ops) when is_number(value), do: safe_math_unary(&:math.tan/1, value)
  def eval("acos", [value], _ops) when is_number(value), do: safe_math_unary(&:math.acos/1, value)
  def eval("asin", [value], _ops) when is_number(value), do: safe_math_unary(&:math.asin/1, value)
  def eval("atan", [value], _ops) when is_number(value), do: safe_math_unary(&:math.atan/1, value)

  def eval("atan2", [y, x], _ops) when is_number(y) and is_number(x),
    do: safe_math_binary(&:math.atan2/2, y, x)

  def eval("logbase", [base, n], _ops) when is_number(base) and is_number(n),
    do: safe_log_base(base, n)

  def eval("degrees", [value], _ops) when is_number(value), do: {:ok, value * :math.pi() / 180.0}
  def eval("radians", [value], _ops) when is_number(value), do: {:ok, value}
  def eval("turns", [value], _ops) when is_number(value), do: {:ok, value * 2.0 * :math.pi()}

  def eval("frompolar", [{radius, theta}], _ops) when is_number(radius) and is_number(theta),
    do: {:ok, {radius * :math.cos(theta), radius * :math.sin(theta)}}

  def eval("topolar", [{x, y}], _ops) when is_number(x) and is_number(y),
    do: {:ok, {:math.sqrt(x * x + y * y), :math.atan2(y, x)}}

  def eval("isnan", [value], _ops),
    do: {:ok, value == :nan or (is_float(value) and value != value)}

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

  defp infinite?(value) when is_float(value),
    do:
      value in [:infinity, :neg_infinity] or
        String.contains?(:erlang.float_to_binary(value, [:compact]) |> String.downcase(), "inf")

  defp infinite?(_), do: false
end
