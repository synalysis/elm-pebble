defmodule Elmx.DictMergeTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Core.Collections
  alias Elmx.Runtime.Generator

  test "dict_merge walks sorted union keys and invokes step closures" do
    left = [{1, :left_only}, {3, :left_both}]
    right = [{2, :right_only}, {3, :right_both}]

    left_step = fn key, value, acc -> [{:left, key, value} | acc] end
    right_step = fn key, value, acc -> acc ++ [{:right, key, value}] end
    both_step = fn key, l, r, acc -> [{:both, key, l, r} | acc] end

    result =
      Collections.dict_merge(left_step, both_step, right_step, left, right, [])

    assert result == [
             {:both, 3, :left_both, :right_both},
             {:left, 1, :left_only},
             {:right, 2, :right_only}
           ]
  end

  test "elmc_dict_merge intrinsic defaults empty accumulator" do
    left = [{1, 10}]
    right = [{2, 20}]

    insert = fn key, value, acc -> Collections.dict_insert(key, value, acc) end
    left_step = insert
    right_step = insert
    both_step = fn key, l, r, acc -> Collections.dict_insert(key, l + r, acc) end

    assert {:ok, merged} =
             Generator.apply("elmc_dict_merge", [left_step, both_step, right_step, left, right])

    assert Collections.dict_get(1, merged) == {:Just, 10}
    assert Collections.dict_get(2, merged) == {:Just, 20}
  end
end
