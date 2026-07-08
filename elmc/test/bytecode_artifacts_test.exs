defmodule Elmc.BytecodeArtifactsTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Bytecode.Artifacts

  @fixture Path.expand("fixtures/simple_project", __DIR__)

  test "read_summary reports manifest metadata" do
    out_dir = Path.expand("tmp/bytecode_artifacts_summary", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmc.compile(@fixture, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :shadow
             })

    summary = Artifacts.read_summary(out_dir)
    assert summary.available == true
    assert summary.contract == "elmc.bytecode_manifest.v1"
    assert summary.function_count > 0
    assert is_map(summary.plan_coverage)
    assert summary.plan_coverage["main"]["total"] > 0
    assert Enum.any?(summary.functions, &(&1.module == "Main" and &1.name == "init"))
  end
end
