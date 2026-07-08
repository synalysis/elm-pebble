defmodule Elmc.BytecodeManifestProgramTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Bytecode.ManifestProgram

  @fixture Path.expand("fixtures/simple_project", __DIR__)

  defp compile_fixture!(opts \\ []) do
    out_dir = Path.expand("tmp/bytecode_manifest_#{System.unique_integer([:positive])}", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmc.compile(@fixture, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: Keyword.get(opts, :strip_dead_code, true),
               plan_ir_mode: :primary
             })

    out_dir
  end

  test "load_linked includes transitive callee sections" do
    build_dir = compile_fixture!(strip_dead_code: false)

    assert {:ok, program} = ManifestProgram.load_linked(build_dir, {"Main", "advanced"})
    assert Map.has_key?(program.sections, {"Main", "helper"})
    assert Map.has_key?(program.sections, {"Main", "advanced"})
    refute Map.has_key?(program.sections, {"Main", "init"})
  end

  test "run dispatches nested call_fn through linked sections" do
    build_dir = compile_fixture!(strip_dead_code: false)

    assert {:ok, program} = ManifestProgram.load_linked(build_dir, {"Main", "advanced"})
    assert {:ok, 8} = ManifestProgram.run(program, {"Main", "advanced"}, params: [5])
    assert {:ok, 11} = ManifestProgram.run(program, {"Main", "advanced"}, params: [9])
  end

  test "run counterOf from manifest without decl_map" do
    build_dir = compile_fixture!()

    assert {:ok, program} = ManifestProgram.load_linked(build_dir, {"Main", "counterOf"})
    model = {:record, [42, nil]}
    assert {:ok, 42} = ManifestProgram.run(program, {"Main", "counterOf"}, params: [model])
  end

  test "function_entries lists manifest functions" do
    build_dir = compile_fixture!()

    assert {:ok, program} = ManifestProgram.load(build_dir)
    entries = ManifestProgram.function_entries(program)

    assert Enum.any?(entries, &(&1["module"] == "Main" and &1["name"] == "counterOf"))
    assert Enum.any?(entries, &(&1["module"] == "Main" and &1["name"] == "init"))
  end
end
