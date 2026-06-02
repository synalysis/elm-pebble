defmodule Elmx.Runtime.Core.Math do
  @moduledoc false

  @spec remainder_by(integer(), integer()) :: integer()
  def remainder_by(base, value) when base != 0, do: rem(value, base)
  def remainder_by(_base, _value), do: 0

  @spec xor(integer(), integer()) :: integer()
  def xor(left, right), do: Bitwise.bxor(left, right)

  @spec to_float(term()) :: float()
  def to_float(n) when is_float(n), do: n
  def to_float(n) when is_integer(n), do: n * 1.0
  def to_float(_), do: 0.0

  @spec floor(term()) :: integer()
  def floor(n) when is_number(n), do: Kernel.floor(n)
  def floor(_), do: 0

  @spec ceiling(term()) :: integer()
  def ceiling(n) when is_number(n), do: Kernel.ceil(n)
  def ceiling(_), do: 0

  @spec round(term()) :: integer()
  def round(n) when is_number(n), do: Kernel.round(n)
  def round(_), do: 0

  @spec truncate(term()) :: integer()
  def truncate(n) when is_number(n), do: trunc(n)
  def truncate(_), do: 0

  @spec sqrt(term()) :: float()
  def sqrt(n) when is_number(n) and n >= 0, do: :math.sqrt(n * 1.0)
  def sqrt(_), do: 0.0

  @spec sin(term()) :: float()
  def sin(n) when is_number(n), do: :math.sin(n * 1.0)

  @spec cos(term()) :: float()
  def cos(n) when is_number(n), do: :math.cos(n * 1.0)

  @spec tan(term()) :: float()
  def tan(n) when is_number(n), do: :math.tan(n * 1.0)

  @spec asin(term()) :: float()
  def asin(n) when is_number(n), do: :math.asin(n * 1.0)

  @spec acos(term()) :: float()
  def acos(n) when is_number(n), do: :math.acos(n * 1.0)

  @spec atan(term()) :: float()
  def atan(n) when is_number(n), do: :math.atan(n * 1.0)

  @spec atan2(term(), term()) :: float()
  def atan2(y, x) when is_number(y) and is_number(x), do: :math.atan2(y * 1.0, x * 1.0)

  @spec degrees(term()) :: float()
  def degrees(radians) when is_number(radians), do: radians * 180.0 / :math.pi()

  @spec radians(term()) :: float()
  def radians(degrees) when is_number(degrees), do: degrees * :math.pi() / 180.0

  @spec turns(term()) :: float()
  def turns(turns) when is_number(turns), do: turns * 2.0 * :math.pi()

  @spec pow(term(), term()) :: float()
  def pow(base, exp) when is_number(base) and is_number(exp), do: :math.pow(base * 1.0, exp * 1.0)

  @spec log_base(term(), term()) :: float()
  def log_base(base, value) when is_number(base) and is_number(value) and base > 0 and value > 0,
    do: :math.log(value * 1.0) / :math.log(base * 1.0)

  def log_base(_base, _value), do: 0.0

  @spec is_infinite(term()) :: boolean()
  def is_infinite(:infinity), do: true
  def is_infinite(:negative_infinity), do: true
  def is_infinite(n) when is_float(n), do: n == :infinity or n == :negative_infinity
  def is_infinite(_), do: false

  @spec is_nan(term()) :: boolean()
  def is_nan(n) when is_float(n), do: n != n
  def is_nan(_), do: false

  @spec to_polar(term()) :: {float(), float()}
  def to_polar(complex) when is_number(complex), do: {abs(complex * 1.0), 0.0}
  def to_polar(_), do: {0.0, 0.0}

  @spec from_polar(term(), term()) :: float()
  def from_polar(magnitude, _angle) when is_number(magnitude), do: magnitude * 1.0
  def from_polar(_, _), do: 0.0
end
