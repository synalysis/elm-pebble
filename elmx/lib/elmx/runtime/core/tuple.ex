defmodule Elmx.Runtime.Core.Tuple do
  @moduledoc false

  alias Elmx.Runtime.Core.Apply

  alias Elmx.Types

  @type pair :: Types.elm_tuple2()

  @spec first(Types.elm_tuple_like()) :: Types.elm_value() | nil
  def first(tuple) when is_tuple(tuple), do: elem(tuple, 0)
  def first([a | _]), do: a
  def first(%{"ctor" => "Tuple", "args" => [a | _]}), do: a
  def first(%{ctor: :Tuple, args: [a | _]}), do: a
  def first(_), do: nil

  @spec second(Types.elm_tuple_like()) :: Types.elm_value() | nil
  def second(tuple) when is_tuple(tuple), do: elem(tuple, 1)
  def second([_, b]), do: b
  def second(%{"ctor" => "Tuple", "args" => [_, b]}), do: b
  def second(%{ctor: :Tuple, args: [_, b]}), do: b
  def second(_), do: nil

  @spec map_first(Types.elm_hof(), Types.elm_tuple2()) :: pair()
  def map_first(fun, tuple) when is_tuple(tuple) do
    {Apply.apply1(fun, elem(tuple, 0)), elem(tuple, 1)}
  end

  @spec map_second(Types.elm_hof(), Types.elm_tuple2()) :: pair()
  def map_second(fun, tuple) when is_tuple(tuple) do
    {elem(tuple, 0), Apply.apply1(fun, elem(tuple, 1))}
  end

  @spec map_both(Types.elm_hof(), Types.elm_hof(), Types.elm_tuple2()) ::
          pair()
  def map_both(fa, fb, tuple) do
    {Apply.apply1(fa, first(tuple)), Apply.apply1(fb, second(tuple))}
  end
end
