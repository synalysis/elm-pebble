defmodule ElmcTest do
  use ExUnit.Case

  test "compile writes runtime, ports, and c outputs" do
    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/build", __DIR__)

    File.rm_rf!(out_dir)

    assert {:ok, %{ir: ir}} = Elmc.compile(project_dir, %{out_dir: out_dir})
    assert length(ir.modules) > 0

    assert File.exists?(Path.join(out_dir, "runtime/elmc_runtime.h"))
    assert File.exists?(Path.join(out_dir, "runtime/elmc_runtime.c"))
    assert File.exists?(Path.join(out_dir, "ports/elmc_ports.h"))
    assert File.exists?(Path.join(out_dir, "ports/elmc_ports.c"))
    assert File.exists?(Path.join(out_dir, "c/elmc_generated.h"))
    assert File.exists?(Path.join(out_dir, "c/elmc_generated.c"))
    assert File.exists?(Path.join(out_dir, "c/elmc_worker.h"))
    assert File.exists?(Path.join(out_dir, "c/elmc_worker.c"))
    assert File.exists?(Path.join(out_dir, "c/elmc_pebble.h"))
    assert File.exists?(Path.join(out_dir, "c/elmc_pebble.c"))
    assert File.exists?(Path.join(out_dir, "c/host_harness.c"))
    assert File.exists?(Path.join(out_dir, "CMakeLists.txt"))
    assert File.exists?(Path.join(out_dir, "Makefile"))
  end

  test "compile strips dead functions by default" do
    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/build_stripped", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir})
    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert String.contains?(generated, "elmc_fn_Main_init")
    assert String.contains?(generated, "elmc_fn_Main_update")
    assert String.contains?(generated, "elmc_fn_Main_view")
    refute String.contains?(generated, "elmc_fn_CoreCompliance_foldSum")
    refute String.contains?(generated, "elmc_fn_CoreCompliance_resultInc")
  end

  test "runtime pruning keeps closure constructor referenced by generated code" do
    out_dir = Path.expand("tmp/runtime_pruned_closure", __DIR__)
    refs_dir = Path.join(out_dir, "refs")
    runtime_dir = Path.join(out_dir, "runtime")

    File.rm_rf!(out_dir)
    File.mkdir_p!(refs_dir)

    File.write!(Path.join(refs_dir, "elmc_generated.c"), """
    #include "elmc_runtime.h"

    ElmcValue *uses_closure(void) {
      return elmc_closure_new(0, 0, 0);
    }
    """)

    assert :ok = Elmc.Runtime.Generator.write_runtime(runtime_dir, prune_from_dir: refs_dir)

    runtime = File.read!(Path.join(runtime_dir, "elmc_runtime.c"))

    assert runtime =~ "ElmcValue *elmc_closure_new"
    assert runtime =~ "ElmcValue *elmc_alloc"
  end
end
