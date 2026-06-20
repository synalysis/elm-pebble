defmodule Elmx.BasicsCompareTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Core
  alias Elmx.Runtime.Generator
  alias Elmx.Runtime.Pebble

  test "basics_compare orders numbers and strings" do
    assert Core.basics_compare(1, 2) == :LT
    assert Core.basics_compare(3, 3) == :EQ
    assert Core.basics_compare(5, 2) == :GT
    assert Core.basics_compare("a", "b") == :LT
    assert Core.basics_compare("z", "a") == :GT
    assert Core.basics_compare("same", "same") == :EQ
    assert Core.basics_compare({:elmx_char, ?a}, {:elmx_char, ?b}) == :LT
    assert Core.basics_compare({:elmx_char, ?c}, {:elmx_char, ?b}) == :GT
  end

  test "sort_with uses Basics.compare via runtime_dispatch" do
    compare = fn a, b -> Pebble.runtime_dispatch("elmx_basics_compare", [a, b]) end

    assert Core.sort_with(compare, ["c", "a", "b"]) == ["a", "b", "c"]
  end

  test "elmc_basics_compare intrinsic matches Core" do
    assert {:ok, :LT} = Generator.apply("elmc_basics_compare", [1, 9])
    assert {:ok, :EQ} = Generator.apply("elmc_basics_compare", ["x", "x"])
    assert {:ok, :GT} = Generator.apply("elmc_basics_compare", [2.5, 1.0])
  end
end
