defmodule Elmx.FnArgPatternEmitTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen
  alias Elmx.Backend.ElixirCodegen.FnArgs

  test "classifies parenthesized constructor params as patterns" do
    assert {:pattern, %{kind: :constructor, name: "Rotation", bind: "angle"}} =
             FnArgs.classify("(Rotation angle)")
  end

  test "emits constructor pattern function heads that bind payload vars" do
    project = Path.expand("test/fixtures/simple_project", Path.dirname(__DIR__))
    {:ok, frontend} = ElmEx.Frontend.Bridge.load_project(project)
    {:ok, ir} = ElmEx.IR.Lowerer.lower_project(frontend)

    assert {:ok, modules} =
             ElixirCodegen.emit_project(ir, %{
               entry_module: "Main",
               mode: :ide_runtime,
               ir_sha256: "fn-arg-pattern",
               # Include Pebble.Ui so the desugared pattern helper is emitted for the assert.
               user_module_names: MapSet.new(["Main", "Pebble.Ui"])
             })

    source =
      modules
      |> Enum.map(& &1.source)
      |> Enum.join("\n")

    # FnArgDesugar rewrites `(Rotation angle)` params into a case on `patternArg`.
    assert source =~ "def elmx_fn_Pebble_Ui_rotationToPebbleAngle(patternArg)"
    assert source =~ "{:Rotation, angle}"
    refute source =~ "def elmx_fn_Pebble_Ui_rotationToPebbleAngle(_unused0)"
  end
end
