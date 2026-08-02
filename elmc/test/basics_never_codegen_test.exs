defmodule Elmc.BasicsNeverCodegenTest do
  @moduledoc """
  `Basics.never` must not lower to a self-recursive C body — GCC
  `-Winfinite-recursion` fails CI host harnesses that compile generated C.
  """

  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile

  @fixture Path.expand("fixtures/pebble_surface_project", __DIR__)

  test "Basics.never is non-recursive in surface fixture generated C" do
    out_dir = Path.expand("tmp/basics_never_codegen", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             CachedCompile.compile(@fixture, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false,
               plan_ir_mode: :primary
             })

    c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert c =~ "elmc_fn_Basics_never"

    refute Regex.match?(
             ~r/elmc_fn_Basics_never\s*\([^)]*\)\s*\{[^}]*elmc_fn_Basics_never\s*\(/s,
             c
           ),
           "Basics.never must not call itself (triggers -Winfinite-recursion)"

    # Body should be a finite unit return (uninhabited Never).
    assert c =~ ~r/static ElmcValue \* elmc_fn_Basics_never\([^)]*\) \{/
  end
end
