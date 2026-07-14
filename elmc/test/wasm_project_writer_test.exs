defmodule Elmc.WasmProjectWriterTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Wasm.{Artifacts, ProjectWriter, Targets}

  @fixture Path.expand("fixtures/simple_project", __DIR__)

  test "emits wasm manifest and wat when target wasm and plan primary" do
    out_dir = Path.expand("tmp/wasm_project_writer", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, result} =
             Elmc.compile(@fixture, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :primary,
               targets: [:wasm]
             })

    assert Targets.wasm_only?(%{targets: [:wasm]})
    refute File.exists?(Path.join(out_dir, "c/elmc_generated.c"))

    manifest_path = ProjectWriter.manifest_path(out_dir)
    assert File.exists?(manifest_path)

    summary = Artifacts.read_summary(out_dir)
    assert summary.available == true
    assert summary.contract == "elmc.wasm_manifest.v1"
    assert summary.function_count > 0
    assert File.exists?(ProjectWriter.wat_path(out_dir))

    assert match?(%{elmc_wasm_summary: %{available: true}}, result)
  end

  test "default c target does not emit wasm artifacts" do
    out_dir = Path.expand("tmp/wasm_project_writer_c_only", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmc.compile(@fixture, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :off
             })

    refute File.exists?(ProjectWriter.manifest_path(out_dir))
    assert %{available: false} = Artifacts.read_summary(out_dir)
  end

  test "c,wasm dual target emits both bytecode hook path and wasm" do
    out_dir = Path.expand("tmp/wasm_project_writer_dual", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmc.compile(@fixture, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :shadow,
               targets: [:c, :wasm]
             })

    assert File.exists?(Path.join(out_dir, "c/elmc_generated.c"))
    assert File.exists?(ProjectWriter.manifest_path(out_dir))
  end
end
