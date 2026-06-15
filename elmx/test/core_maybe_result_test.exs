defmodule Elmx.CoreMaybeResultTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Core
  alias Elmx.Runtime.Core.MaybeResult
  alias Elmx.Runtime.Intrinsics

  test "maybe_map via Core delegate" do
    f = fn x -> x + 1 end
    assert Core.maybe_map(f, {:Just, 2}) == {:Just, 3}
    assert Core.maybe_map(f, :Nothing) == :Nothing
  end

  test "result_to_maybe via MaybeResult module" do
    assert MaybeResult.result_to_maybe({:Ok, 1}) == {:Just, 1}
    assert MaybeResult.result_to_maybe({:Err, :x}) == :Nothing
  end

  test "elmc intrinsics route to MaybeResult" do
    assert {:ok, :Nothing} = Intrinsics.apply("elmc_result_to_maybe", [{:Err, :bad}])
    assert {:ok, {:Just, 7}} = Intrinsics.apply("elmc_result_to_maybe", [{:Ok, 7}])
  end
end
