defmodule Elmx.Runtime.Core.Math do
  @moduledoc false

  alias Elmx.Types

  @spec remainder_by(integer(), integer()) :: integer()
  def remainder_by(base, value) when base != 0, do: rem(value, base)
  def remainder_by(_base, _value), do: 0

  # Elm `Basics.xor : Bool -> Bool -> Bool` (not bitwise).
  @spec xor(term(), term()) :: boolean()
  def xor(left, right), do: as_bool(left) != as_bool(right)

  @spec to_float(Types.numeric_input()) :: float()
  def to_float(n) when is_float(n), do: n
  def to_float(n) when is_integer(n), do: n * 1.0
  def to_float(_), do: 0.0

  @spec floor(Types.numeric_input()) :: integer()
  def floor(n) when is_number(n), do: Kernel.floor(n)
  def floor(_), do: 0

  @spec ceiling(Types.numeric_input()) :: integer()
  def ceiling(n) when is_number(n), do: Kernel.ceil(n)
  def ceiling(_), do: 0

  @spec round(Types.numeric_input()) :: integer()
  def round(n) when is_number(n), do: Kernel.round(n)
  def round(_), do: 0

  @spec truncate(Types.numeric_input()) :: integer()
  def truncate(n) when is_number(n), do: trunc(n)
  def truncate(_), do: 0

  @spec sqrt(Types.numeric_input()) :: float() | :nan
  def sqrt(n) when is_number(n) and n >= 0, do: :math.sqrt(n * 1.0)
  def sqrt(n) when is_number(n) and n < 0, do: :nan
  def sqrt(_), do: :nan

  @spec fdiv(number(), number()) :: float() | :infinity | :negative_infinity | :nan
  # Elm: 0/0 is NaN (must precede the infinity clauses).
  def fdiv(a, b) when is_number(a) and is_number(b) and a == 0 and b == 0, do: :nan
  def fdiv(a, 0) when is_number(a) and a < 0, do: :negative_infinity
  def fdiv(_a, 0), do: :infinity
  def fdiv(a, +0.0) when is_number(a) and a < 0, do: :negative_infinity
  def fdiv(_a, +0.0), do: :infinity

  def fdiv(a, b) when is_number(a) and is_number(b), do: a * 1.0 / (b * 1.0)

  @spec sin(Types.numeric_input()) :: float()
  def sin(n) when is_number(n), do: :math.sin(n * 1.0)

  @spec cos(Types.numeric_input()) :: float()
  def cos(n) when is_number(n), do: :math.cos(n * 1.0)

  @spec tan(Types.numeric_input()) :: float()
  def tan(n) when is_number(n), do: :math.tan(n * 1.0)

  @spec asin(Types.numeric_input()) :: float() | :nan
  def asin(n) when is_number(n) do
    x = n * 1.0

    cond do
      x > 1.0 or x < -1.0 -> :nan
      true -> :math.asin(x)
    end
  end

  def asin(_), do: :nan

  @spec acos(Types.numeric_input()) :: float() | :nan
  def acos(n) when is_number(n) do
    x = n * 1.0

    cond do
      x > 1.0 or x < -1.0 -> :nan
      true -> :math.acos(x)
    end
  end

  def acos(_), do: :nan

  @spec atan(Types.numeric_input()) :: float()
  def atan(n) when is_number(n), do: :math.atan(n * 1.0)

  @spec atan2(Types.numeric_input(), Types.numeric_input()) :: float()
  def atan2(y, x) when is_number(y) and is_number(x), do: :math.atan2(y * 1.0, x * 1.0)

  # Elm Basics.degrees: degrees → radians (standard Elm angle units).
  @spec degrees(Types.numeric_input()) :: float()
  def degrees(angle_in_degrees) when is_number(angle_in_degrees),
    do: angle_in_degrees * :math.pi() / 180.0

  # Elm Basics.radians: already radians → identity.
  @spec radians(Types.numeric_input()) :: float()
  def radians(angle_in_radians) when is_number(angle_in_radians), do: angle_in_radians * 1.0

  @spec turns(Types.numeric_input()) :: float()
  def turns(turns) when is_number(turns), do: turns * 2.0 * :math.pi()

  @spec pow(Types.numeric_input(), Types.numeric_input()) :: float()
  def pow(base, exp) when is_number(base) and is_number(exp), do: :math.pow(base * 1.0, exp * 1.0)

  @spec log(Types.numeric_input()) :: float() | :nan
  def log(n) when is_number(n) and n > 0, do: :math.log(n * 1.0)
  def log(_), do: :nan

  @spec log_base(Types.numeric_input(), Types.numeric_input()) :: float()
  def log_base(base, value) when is_number(base) and is_number(value) and base > 0 and value > 0,
    do: :math.log(value * 1.0) / :math.log(base * 1.0)

  def log_base(_base, _value), do: 0.0

  @spec is_infinite(Types.float_marker() | number()) :: boolean()
  def is_infinite(:infinity), do: true
  def is_infinite(:negative_infinity), do: true
  def is_infinite(n) when is_float(n) do
    case :erlang.float_to_binary(n, [:compact]) do
      "inf" -> true
      "-inf" -> true
      _ -> false
    end
  end
  def is_infinite(_), do: false

  @spec is_nan(float() | number()) :: boolean()
  def is_nan(:nan), do: true
  def is_nan(n) when is_float(n), do: n != n
  def is_nan(_), do: false

  # Elm `toPolar (x, y) -> (r, θ)` with θ = atan2 y x.
  @spec to_polar({number(), number()} | term()) :: {float(), float()}
  def to_polar({x, y}) when is_number(x) and is_number(y) do
    xf = x * 1.0
    yf = y * 1.0
    {:math.sqrt(xf * xf + yf * yf), :math.atan2(yf, xf)}
  end

  def to_polar(_), do: {0.0, 0.0}

  # Elm `fromPolar (r, θ) -> (x, y)`; codegen may pass the pair as two args.
  @spec from_polar(Types.numeric_input(), Types.numeric_input()) :: {float(), float()}
  def from_polar(magnitude, angle) when is_number(magnitude) and is_number(angle) do
    r = magnitude * 1.0
    theta = angle * 1.0
    {r * :math.cos(theta), r * :math.sin(theta)}
  end

  def from_polar(_, _), do: {0.0, 0.0}

  defp as_bool(true), do: true
  defp as_bool(false), do: false
  defp as_bool(n) when is_integer(n), do: n != 0
  defp as_bool(_), do: false
end
