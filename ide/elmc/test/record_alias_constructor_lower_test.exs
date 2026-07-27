defmodule Elmc.RecordAliasConstructorLowerTest do
  use ExUnit.Case, async: true

  test "type-alias record constructors lower for WASM (no constructor tags required)" do
    project_dir =
      Path.expand("fixtures/record_alias_ctor_project", __DIR__)

    out_dir = Path.join(System.tmp_dir!(), "elmc_record_alias_ctor_wasm")
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               targets: [:wasm],
               web: true,
               entry_module: "Main",
               strip_dead_code: false
             })

    reasons = Process.get(:elmc_plan_unsupported_reasons, %{})

    refute Enum.any?(reasons, fn
             {{_m, _n}, %{op: :constructor_call, target: "Person"}} -> true
             _ -> false
           end),
           "record alias ctor Person must be rewritten/lowered (not left as constructor_call)"
  end
end

