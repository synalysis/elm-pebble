defmodule Elmx.BasicsCompareTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Core
  alias Elmx.Runtime.Generator
  alias Elmx.Runtime.Pebble

  test "basics_compare orders numbers and strings" do
    assert Core.basics_compare(1, 2) == -1
    assert Core.basics_compare(3, 3) == 0
    assert Core.basics_compare(5, 2) == 1
    assert Core.basics_compare("a", "b") == -1
    assert Core.basics_compare("z", "a") == 1
    assert Core.basics_compare("same", "same") == 0
  end

  test "sort_with uses Basics.compare via runtime_dispatch" do
    compare = fn a, b ->
      case Pebble.runtime_dispatch("elmx_basics_compare", [a, b]) do
        -1 -> :LT
        0 -> :EQ
        1 -> :GT
      end
    end

    assert Core.sort_with(compare, ["c", "a", "b"]) == ["a", "b", "c"]
  end

  test "elmc_basics_compare intrinsic matches Core" do
    assert {:ok, -1} = Generator.apply("elmc_basics_compare", [1, 9])
    assert {:ok, 0} = Generator.apply("elmc_basics_compare", ["x", "x"])
    assert {:ok, 1} = Generator.apply("elmc_basics_compare", [2.5, 1.0])
  end
end
