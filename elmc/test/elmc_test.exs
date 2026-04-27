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
end
