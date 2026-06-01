defmodule Elmx.Runtime.Core.Tuple do
  @moduledoc false

  alias Elmx.Runtime.Core

  @spec first(term()) :: term()
  def first(tuple) when is_tuple(tuple), do: elem(tuple, 0)
  def first([a | _]), do: a
  def first(%{"ctor" => "Tuple", "args" => [a | _]}), do: a
  def first(%{ctor: :Tuple, args: [a | _]}), do: a
  def first(_), do: nil

  @spec second(term()) :: term()
  def second(tuple) when is_tuple(tuple), do: elem(tuple, 1)
  def second([_, b]), do: b
  def second(%{"ctor" => "Tuple", "args" => [_, b]}), do: b
  def second(%{ctor: :Tuple, args: [_, b]}), do: b
  def second(_), do: nil

  @spec map_first(term(), term()) :: term()
  def map_first(fun, tuple) when is_tuple(tuple) do
    {Core.apply1(fun, elem(tuple, 0)), elem(tuple, 1)}
  end

  @spec map_second(term(), term()) :: term()
  def map_second(fun, tuple) when is_tuple(tuple) do
    {elem(tuple, 0), Core.apply1(fun, elem(tuple, 1))}
  end

  @spec map_both(term(), term(), term()) :: term()
  def map_both(fa, fb, tuple) do
    {Core.apply1(fa, first(tuple)), Core.apply1(fb, second(tuple))}
  end
end
