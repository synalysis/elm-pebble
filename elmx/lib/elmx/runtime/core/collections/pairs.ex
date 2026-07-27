defmodule Elmx.Runtime.Core.Collections.Pairs do
  @moduledoc false
  alias Elmx.Types, as: Types


  @spec normalize_pair(term() | map()) :: term()

  def normalize_pair({a, b}), do: {a, b}
  def normalize_pair([a, b]), do: {a, b}
  def normalize_pair(%{"ctor" => "Tuple", "args" => [a, b]}), do: {a, b}
  def normalize_pair(%{ctor: :Tuple, args: [a, b]}), do: {a, b}
  def normalize_pair(_), do: {0, nil}

  @spec to_int(integer() | float() | map() | term() | Types.elm_value(), Types.elm_value()) :: Types.elm_value()

  def to_int(n, _default) when is_integer(n), do: n
  def to_int(n, _default) when is_float(n), do: trunc(n)
  def to_int(%{"ctor" => "Ok", "args" => [inner]}, default), do: to_int(inner, default)
  def to_int({:Ok, inner}, default), do: to_int(inner, default)
  def to_int(_other, default), do: default
end
