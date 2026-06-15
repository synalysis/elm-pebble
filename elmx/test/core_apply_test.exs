defmodule Elmx.CoreApplyTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Core
  alias Elmx.Runtime.Core.Apply

  test "Core delegates apply helpers to Core.Apply" do
    assert Core.apply2(fn a, b -> a + b end, 2, 3) == 5
    assert Apply.apply2(fn a, b -> a + b end, 2, 3) == 5
  end

  test "apply1 rejects still-curried unary callbacks" do
    assert_raise ArgumentError, fn ->
      Apply.apply1(fn _ -> fn _ -> :ok end end, 1)
    end
  end
end
