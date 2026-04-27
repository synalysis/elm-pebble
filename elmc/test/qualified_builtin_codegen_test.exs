defmodule Elmc.QualifiedBuiltinCodegenTest do
  use ExUnit.Case

  test "qualified Basics operators are lowered as builtins" do
    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/qualified_builtin_codegen", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _result} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    refute generated_c =~ "elmc_fn_Basics___mul__"
    refute generated_c =~ "elmc_fn_Basics___add__"
    refute generated_c =~ "elmc_fn_Basics___idiv__"
  end
end
