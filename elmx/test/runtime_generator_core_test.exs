defmodule Elmx.RuntimeGeneratorCoreTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Generator
  alias Elmx.Runtime.Core.Collections

  test "dict insert/get/size parity" do
    dict = Collections.dict_from_list([{1, 10}, {2, 20}])
    dict = Collections.dict_insert(1, 99, dict)
    assert {:ok, true} = Generator.apply("elmc_dict_member", [1, dict])
    assert {:ok, 2} = Generator.apply("elmc_dict_size", [dict])
    assert {:ok, {:Just, 99}} = Generator.apply("elmc_dict_get", [1, dict])
  end

  test "set and array parity" do
    assert {:ok, true} = Generator.apply("elmc_set_member", [2, [1, 2, 3]])
    assert {:ok, 3} = Generator.apply("elmc_array_length", [[:a, :b, :c]])
    assert {:ok, [:a, :b, :c, :d]} = Generator.apply("elmc_array_push", [:d, [:a, :b, :c]])
  end

  test "string and bitwise parity" do
    assert {:ok, "hi!"} = Generator.apply("elmc_append", ["hi", "!"])
    assert {:ok, true} = Generator.apply("elmc_string_is_empty", [""])
    assert {:ok, 15} = Generator.apply("elmc_bitwise_and", [31, 15])
  end
end
