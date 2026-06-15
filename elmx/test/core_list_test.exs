defmodule Elmx.CoreListTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Core
  alias Elmx.Runtime.Core.List

  test "Core delegates list helpers to Core.List" do
    assert Core.list_head([1, 2, 3]) == {:Just, 1}
    assert List.list_head([1, 2, 3]) == {:Just, 1}
    assert Core.list_sum([1, 2, 3]) == 6
    assert Core.map(&(&1 * 2), [1, 2]) == [2, 4]
  end
end
