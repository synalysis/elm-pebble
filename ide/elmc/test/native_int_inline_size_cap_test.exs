defmodule Elmc.NativeIntInlineSizeCapTest do
  use ExUnit.Case, async: true

  alias Elmc.TestSupport.TangramTemplate

  test "tangram text scoring avoids inlined pointPenalty expansions" do
    project_dir = TangramTemplate.scaffold_project()

    out_dir = Path.expand("tmp/native_int_inline_cap_codegen", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    refute generated_c =~ "// inlined Main.pointPenalty"
  end
end
