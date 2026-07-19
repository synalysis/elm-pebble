defmodule Ide.Debugger.BytecodeApiTest do
  use ExUnit.Case, async: false

  alias Ide.Debugger.{BytecodeApi, BytecodeRunner}

  @elmc_fixture Path.expand("../../../../elmc/test/fixtures/simple_project", __DIR__)
  @default_model {:record, [nil, 0, 0, 0, 0, 0, 0, nil]}

  test "default_params supplies model tuple for Model params" do
    assert BytecodeApi.default_params(%{"params" => ["model"]}) == [@default_model]
    assert BytecodeApi.default_params(%{"params" => ["n"]}) == [0]
    assert BytecodeApi.default_params(nil) == []
  end

  test "default_params drive linked bytecode smoke run" do
    build_dir = Path.expand("tmp/ide_bytecode_api", __DIR__)
    File.rm_rf!(build_dir)

    assert {:ok, _} =
             Elmc.compile(@elmc_fixture, %{
               out_dir: build_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :primary
             })

    params = BytecodeApi.default_params(%{"params" => ["model"]})

    assert {:ok, {:record, [13, 26, -9, 3]}} =
             BytecodeRunner.run(build_dir, {"Main", "boardLayout"}, params: params)
  end
end
