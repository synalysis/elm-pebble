defmodule Elmx.Runtime.Core.Math do
  @moduledoc false

  alias Elmx.Types

  @spec remainder_by(integer(), integer()) :: integer()
  def remainder_by(base, value) when base != 0, do: rem(value, base)
  def remainder_by(_base, _value), do: 0

  @spec xor(integer(), integer()) :: integer()
  def xor(left, right), do: Bitwise.bxor(left, right)

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

  @spec sqrt(Types.numeric_input()) :: float()
  def sqrt(n) when is_number(n) and n >= 0, do: :math.sqrt(n * 1.0)
  def sqrt(_), do: 0.0

  @spec sin(Types.numeric_input()) :: float()
  def sin(n) when is_number(n), do: :math.sin(n * 1.0)

  @spec cos(Types.numeric_input()) :: float()
  def cos(n) when is_number(n), do: :math.cos(n * 1.0)

  @spec tan(Types.numeric_input()) :: float()
  def tan(n) when is_number(n), do: :math.tan(n * 1.0)

  @spec asin(Types.numeric_input()) :: float()
  def asin(n) when is_number(n), do: :math.asin(n * 1.0)

  @spec acos(Types.numeric_input()) :: float()
  def acos(n) when is_number(n), do: :math.acos(n * 1.0)

  @spec atan(Types.numeric_input()) :: float()
  def atan(n) when is_number(n), do: :math.atan(n * 1.0)

  @spec atan2(Types.numeric_input(), Types.numeric_input()) :: float()
  def atan2(y, x) when is_number(y) and is_number(x), do: :math.atan2(y * 1.0, x * 1.0)

  @spec degrees(Types.numeric_input()) :: float()
  def degrees(radians) when is_number(radians), do: radians * 180.0 / :math.pi()

  @spec radians(Types.numeric_input()) :: float()
  def radians(degrees) when is_number(degrees), do: degrees * :math.pi() / 180.0

  @spec turns(Types.numeric_input()) :: float()
  def turns(turns) when is_number(turns), do: turns * 2.0 * :math.pi()

  @spec pow(Types.numeric_input(), Types.numeric_input()) :: float()
  def pow(base, exp) when is_number(base) and is_number(exp), do: :math.pow(base * 1.0, exp * 1.0)

  @spec log_base(Types.numeric_input(), Types.numeric_input()) :: float()
  def log_base(base, value) when is_number(base) and is_number(value) and base > 0 and value > 0,
    do: :math.log(value * 1.0) / :math.log(base * 1.0)

  def log_base(_base, _value), do: 0.0

  @spec is_infinite(Types.float_marker() | term()) :: boolean()
  def is_infinite(:infinity), do: true
  def is_infinite(:negative_infinity), do: true
  def is_infinite(_), do: false

  @spec is_nan(float() | term()) :: boolean()
  def is_nan(n) when is_float(n), do: n != n
  def is_nan(_), do: false

  @spec to_polar(Types.numeric_input()) :: {float(), float()}
  def to_polar(complex) when is_number(complex), do: {abs(complex * 1.0), 0.0}
  def to_polar(_), do: {0.0, 0.0}

  @spec from_polar(Types.numeric_input(), Types.numeric_input()) :: float()
  def from_polar(magnitude, _angle) when is_number(magnitude), do: magnitude * 1.0
  def from_polar(_, _), do: 0.0
end
