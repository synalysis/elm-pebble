defmodule Elmc.MaybeWithDefaultRcOwnershipTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.RuntimeCall.Core, as: RuntimeCall
  alias Elmc.Backend.CCodegen.ValueSlots

  test "elmc_maybe_with_default drops retain only inside owned-default alias if" do
    ValueSlots.reset(epilogue_lifo: true)
    {_default, _} = ValueSlots.alloc()
    {_maybe, _} = ValueSlots.alloc()

    expr = %{
      op: :runtime_call,
      function: "elmc_maybe_with_default",
      args: [
        %{op: :var, name: "default_val"},
        %{op: :var, name: "maybe"}
      ]
    }

    env = %{
      "default_val" => "owned[0]",
      "maybe" => "owned[1]",
      __rc_required__: true,
      __rc_catch__: true
    }

    {code, _out, _counter} = RuntimeCall.compile(expr, env, 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "owned[2] = elmc_maybe_with_default(owned[0], owned[1])"
    # Release must live inside the alias transfer — unconditional release frees a
    # Just payload borrow while the model still owns it (YES drawDial sun).
    assert source =~ ~r/if \(owned\[2\] == owned\[0\]\) \{\s*elmc_release\(owned\[2\]\);/
    refute source =~ ~r/elmc_release\(owned\[2\]\);\s*if \(owned\[2\] == owned\[0\]\)/
  end

  test "elmc_maybe_with_default with borrowed maybe keeps Just retain (no bare release)" do
    ValueSlots.reset(epilogue_lifo: true)
    {_default, _} = ValueSlots.alloc()

    expr = %{
      op: :runtime_call,
      function: "elmc_maybe_with_default",
      args: [
        %{op: :var, name: "default_val"},
        %{op: :var, name: "maybe"}
      ]
    }

    env = %{
      "default_val" => "owned[0]",
      # Borrowed record field — not an owned slot, so no alias null for maybe.
      "maybe" => "model_sun",
      __rc_required__: true,
      __rc_catch__: true
    }

    {code, _out, _counter} = RuntimeCall.compile(expr, env, 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "owned[1] = elmc_maybe_with_default(owned[0], model_sun)"
    assert source =~ ~r/if \(owned\[1\] == owned\[0\]\) \{\s*elmc_release\(owned\[1\]\);/
    refute source =~ ~r/elmc_release\(owned\[1\]\);\s*\n\s*if \(owned\[1\] == owned\[0\]\)/
  end
end
