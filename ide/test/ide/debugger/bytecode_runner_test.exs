defmodule Ide.Debugger.BytecodeRunnerTest do
  use ExUnit.Case, async: false

  alias Ide.Debugger.BytecodeRunner

  @elmc_fixture Path.expand("../../../../elmc/test/fixtures/simple_project", __DIR__)

  test "runner executes counterOf from emitted bytecode manifest" do
    build_dir = Path.expand("tmp/ide_bytecode_runner", __DIR__)
    File.rm_rf!(build_dir)

    assert {:ok, _} =
             Elmc.compile(@elmc_fixture, %{
               out_dir: build_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :shadow
             })

    assert BytecodeRunner.available?(build_dir)

    summary = BytecodeRunner.summary(build_dir)
    assert summary.available == true
    assert summary.function_count > 0

    assert {:ok, 3} =
             BytecodeRunner.run(build_dir, {"Main", "counterOf"}, params: [{:record, [3, nil]}])

    functions = BytecodeRunner.functions(build_dir)
    assert Enum.any?(functions, &(&1["module"] == "Main" and &1["name"] == "counterOf"))
  end

  test "runner links nested callees for advanced" do
    build_dir = Path.expand("tmp/ide_bytecode_runner_advanced", __DIR__)
    File.rm_rf!(build_dir)

    assert {:ok, _} =
             Elmc.compile(@elmc_fixture, %{
               out_dir: build_dir,
               entry_module: "Main",
               strip_dead_code: false,
               plan_ir_mode: :primary
             })

    assert {:ok, 8} = BytecodeRunner.run(build_dir, {"Main", "advanced"}, params: [5])
    assert {:ok, 11} = BytecodeRunner.run(build_dir, {"Main", "advanced"}, params: [9])
  end
end
