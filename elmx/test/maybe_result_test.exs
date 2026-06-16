defmodule Elmx.Runtime.Core.MaybeResultTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Core.MaybeResult

  test "maybe_map2 combines tuple and wire Just values without looping" do
    f = fn a, b -> {a, b} end

    assert {:Just, {1, 2}} =
             MaybeResult.maybe_map2({:Just, 1}, %{"ctor" => "Just", "args" => [2]}, f)
  end

  test "maybe_map2 applies curried Elm constructors" do
    ctor = fn x -> fn y -> %{x: x, y: y} end end

    assert {:Just, %{x: 58.0, y: 52.0}} =
             MaybeResult.maybe_map2({:Just, 58.0}, {:Just, 52.0}, ctor)
  end

  test "maybe_map2 returns Nothing when callback is not a function" do
    assert :Nothing =
             MaybeResult.maybe_map2({:Just, 1}, {:Just, 2}, :not_a_function)
  end
end
