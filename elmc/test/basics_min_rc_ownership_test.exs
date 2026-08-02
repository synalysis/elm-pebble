defmodule Elmc.BasicsMinRcOwnershipTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.RuntimeCall.Core, as: RuntimeCall
  alias Elmc.Backend.CCodegen.ValueSlots

  test "elmc_basics_min on owned epilogue slots drops retain before alias null" do
    ValueSlots.reset(epilogue_lifo: true)
    {_left, _} = ValueSlots.alloc()
    {_right, _} = ValueSlots.alloc()

    expr = %{
      op: :runtime_call,
      function: "elmc_basics_min",
      args: [
        %{op: :var, name: "left"},
        %{op: :var, name: "right"}
      ]
    }

    env = %{
      "left" => "owned[0]",
      "right" => "owned[1]",
      __rc_required__: true,
      __rc_catch__: true
    }

    {code, out, _counter} = RuntimeCall.compile(expr, env, 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "elmc_basics_min(&#{out}, owned[0], owned[1])"
    assert source =~ "CHECK_RC(Rc)"
    assert source =~ ~r/if \(#{Regex.escape(out)} == owned\[0\]\) \{\s*elmc_release\(#{Regex.escape(out)}\);/
    assert source =~ ~r/if \(#{Regex.escape(out)} == owned\[1\]\) \{\s*elmc_release\(#{Regex.escape(out)}\);/
    refute source =~ ~r/elmc_release\(#{Regex.escape(out)}\);\s*if \(#{Regex.escape(out)} == owned\[0\]\)/
  end
end
