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

  test "maybe_map3 through map5 combine only when all inputs are Just" do
    assert {:Just, 6} =
             MaybeResult.maybe_map3(fn a, b, c -> a + b + c end, {:Just, 1}, {:Just, 2}, {:Just, 3})

    assert :Nothing =
             MaybeResult.maybe_map3(fn a, b, c -> a + b + c end, {:Just, 1}, :Nothing, {:Just, 3})

    assert {:Just, 10} =
             MaybeResult.maybe_map4(fn a, b, c, d -> a + b + c + d end, {:Just, 1}, {:Just, 2}, {:Just, 3}, {:Just, 4})

    assert {:Just, 15} =
             MaybeResult.maybe_map5(fn a, b, c, d, e -> a + b + c + d + e end, {:Just, 1}, {:Just, 2}, {:Just, 3}, {:Just, 4}, {:Just, 5})
  end

  test "result_map2 through map5 preserve first Err" do
    assert {:Ok, 7} = MaybeResult.result_map2(&+/2, {:Ok, 3}, {:Ok, 4})
    assert {:Err, :left} = MaybeResult.result_map2(&+/2, {:Err, :left}, {:Ok, 4})
    assert {:Ok, 6} = MaybeResult.result_map3(fn a, b, c -> a + b + c end, {:Ok, 1}, {:Ok, 2}, {:Ok, 3})
    assert {:Ok, 10} = MaybeResult.result_map4(fn a, b, c, d -> a + b + c + d end, {:Ok, 1}, {:Ok, 2}, {:Ok, 3}, {:Ok, 4})
    assert {:Ok, 15} = MaybeResult.result_map5(fn a, b, c, d, e -> a + b + c + d + e end, {:Ok, 1}, {:Ok, 2}, {:Ok, 3}, {:Ok, 4}, {:Ok, 5})
  end
end
