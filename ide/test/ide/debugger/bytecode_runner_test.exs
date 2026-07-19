defmodule Ide.Debugger.BytecodeRunnerTest do
  use ExUnit.Case, async: false

  alias Ide.Debugger.BytecodeRunner

  @elmc_fixture Path.expand("../../../../elmc/test/fixtures/simple_project", __DIR__)

  test "runner executes randomIndex from emitted bytecode manifest" do
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
             BytecodeRunner.run(build_dir, {"Main", "randomIndex"}, params: [10, 3])

    functions = BytecodeRunner.functions(build_dir)
    assert Enum.any?(functions, &(&1["module"] == "Main" and &1["name"] == "randomIndex"))
  end

  test "runner links nested callees for spawnTileWithSeed" do
    build_dir = Path.expand("tmp/ide_bytecode_runner_advanced", __DIR__)
    File.rm_rf!(build_dir)

    assert {:ok, _} =
             Elmc.compile(@elmc_fixture, %{
               out_dir: build_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :primary
             })

    cells = List.duplicate(0, 16)

    assert {:ok, {:tuple2, board, _seed}} =
             BytecodeRunner.run(build_dir, {"Main", "spawnTileWithSeed"}, params: [12345, cells])

    assert Enum.at(board, 10) == 2
  end
end
