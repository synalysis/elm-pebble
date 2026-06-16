defmodule Elmc.NativeIntInlineSizeCapTest do
  use ExUnit.Case, async: true

  test "tangram text scoring avoids inlined pointPenalty expansions" do
    project_dir = Path.expand("../../ide/workspace_projects/tangram/watch", __DIR__)

    out_dir = Path.expand("tmp/native_int_inline_cap_codegen", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               strip_dead_code: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    refute generated_c =~ "// inlined Main.pointPenalty"
  end
end
