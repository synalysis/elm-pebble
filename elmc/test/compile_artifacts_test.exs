defmodule Elmc.CompileArtifactsTest do
  use ExUnit.Case, async: false

  alias Elmc.CLI

  @fixture_dir Path.expand("fixtures/simple_project", __DIR__)

  test "clean compile populates empty blocking diagnostics" do
    out_dir = Path.expand("tmp/compile_artifacts_blocking_out", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, result} =
             Elmc.compile(@fixture_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :primary,
               plan_ir_strict: true
             })

    assert result.blocking_diagnostics == []
    assert is_list(result.informational_diagnostics)
    assert :ok = CLI.validate_compile_result(result)

    assert {:ok, artifact_result} =
             CLI.compile_artifacts_with_opts_impl(@fixture_dir, %{out_dir: out_dir})

    assert artifact_result.blocking_diagnostics == []
  after
    File.rm_rf!(Path.expand("tmp/compile_artifacts_blocking_out", __DIR__))
  end
end
