defmodule Elmx.Runtime.Core.Collections.Pairs do
  @moduledoc false

  def normalize_pair({a, b}), do: {to_int(a, 0), b}
  def normalize_pair([a, b]), do: {to_int(a, 0), b}
  def normalize_pair(%{"ctor" => "Tuple", "args" => [a, b]}), do: {to_int(a, 0), b}
  def normalize_pair(%{ctor: :Tuple, args: [a, b]}), do: {to_int(a, 0), b}
  def normalize_pair(_), do: {0, nil}

  def to_int(n, _default) when is_integer(n), do: n
  def to_int(n, _default) when is_float(n), do: trunc(n)
  def to_int(%{"ctor" => "Ok", "args" => [inner]}, default), do: to_int(inner, default)
  def to_int({:Ok, inner}, default), do: to_int(inner, default)
  def to_int(other, _default) when is_number(other), do: trunc(other)
  def to_int(_other, default), do: default
end
