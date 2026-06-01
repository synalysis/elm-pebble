defmodule Elmx.StdlibRuntimeCallPartsTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Stdlib

  test "round preserves commas inside nested runtime_dispatch args" do
    arg =
      "(:math.sin(theta) * Elmx.Runtime.Pebble.runtime_dispatch(\"elmx_basics_to_float\", [radius]))"

    code = Stdlib.runtime_call_parts("elmx_basics_round", [arg])

    assert code =~ "runtime_dispatch(\"elmx_basics_to_float\", [radius])"
    assert code =~ "round(("
    assert String.ends_with?(code, "))")
  end

  test "split_top_level_args respects nested brackets" do
    assert Stdlib.runtime_call(
             "elmx_basics_to_float",
             "Elmx.Runtime.Pebble.runtime_dispatch(\"other\", [1, 2])"
           ) ==
             "Elmx.Runtime.Pebble.runtime_dispatch(\"elmx_basics_to_float\", [Elmx.Runtime.Pebble.runtime_dispatch(\"other\", [1, 2])])"
  end
end
