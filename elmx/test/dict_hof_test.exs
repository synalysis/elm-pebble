defmodule Elmx.DictHofTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Core
  alias Elmx.Runtime.Core.Collections
  alias Elmx.Runtime.Generator

  test "dict_map passes key and value to the step function" do
    dict = [{1, 10}, {2, 20}]

    mapped =
      Collections.dict_map(
        fn key, value -> value + key end,
        dict
      )

    assert mapped == [{1, 11}, {2, 22}]
  end

  test "dict_foldl and dict_filter use separate key and value args" do
    dict = [{1, 2}, {3, 4}, {5, 6}]

    assert Collections.dict_foldl(fn _k, v, acc -> acc + v end, 0, dict) == 12

    assert Collections.dict_filter(fn k, _v -> rem(k, 2) == 1 end, dict) == [{1, 2}, {3, 4}, {5, 6}]

    {yes, no} = Collections.dict_partition(fn k, _v -> k <= 3 end, dict)
    assert yes == [{1, 2}, {3, 4}]
    assert no == [{5, 6}]
  end

  test "elmc_dict_map intrinsic matches Collections.dict_map" do
    dict = [{0, 5}]

    assert {:ok, mapped} =
             Generator.apply("elmc_dict_map", [fn k, v -> k + v end, dict])

    assert mapped == [{0, 5}]
  end

  test "curried dict_map step still works via Core.apply2" do
    dict = [{2, 3}]
    step = fn k -> fn v -> k * v end end
    assert [{2, 6}] = Enum.map(dict, fn {k, v} -> {k, Core.apply2(step, k, v)} end)
  end

  test "dict_update applies Maybe alter and removes on Nothing" do
    dict = [{1, 10}, {2, 20}]

    inc_existing =
      Collections.dict_update(
        1,
        fn
          {:Just, value} -> {:Just, value + 1}
          :Nothing -> {:Just, 0}
        end,
        dict
      )

    assert Collections.dict_get(1, inc_existing) == {:Just, 11}
    assert Collections.dict_get(2, inc_existing) == {:Just, 20}

    removed =
      Collections.dict_update(
        2,
        fn _ -> :Nothing end,
        inc_existing
      )

    assert Collections.dict_member(2, removed) == false
    assert Collections.dict_get(1, removed) == {:Just, 11}
  end

  test "elmc_dict_update intrinsic matches Collections.dict_update" do
    dict = [{3, 7}]

    assert {:ok, updated} =
             Generator.apply("elmc_dict_update", [
               3,
               fn {:Just, value} -> {:Just, value + 3} end,
               dict
             ])

    assert Collections.dict_get(3, updated) == {:Just, 10}
  end
end
