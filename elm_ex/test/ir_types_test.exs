defmodule ElmEx.IRTypesTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.{AstContract, GeneratedParser, Project}
  alias ElmEx.Frontend.{GeneratedParser, Project}
  alias ElmEx.IR.Lowerer

  test "lower_project produces typed IR module declarations" do
    source = """
    module Main exposing (main)

    type Msg = Tick

    main = 0
    """

    assert {:ok, module} = GeneratedParser.parse_source("Main.elm", source)
    assert :ok = AstContract.validate_module(module)

    project = %Project{
      project_dir: "/tmp",
      elm_json: %{},
      modules: [module],
      diagnostics: []
    }

    assert {:ok, ir} = Lowerer.lower_project(project)
    assert [ir_module | _] = ir.modules
    assert %ElmEx.IR.Module{} = ir_module
    assert ir_module.name == "Main"
    assert is_map(ir_module.unions)
    assert Enum.any?(ir_module.declarations, &(&1.kind == :function and &1.name == "main"))
  end

  test "lower_project attaches IR diagnostics list" do
    source = """
    module Main exposing (main)

    main = unknownFn 1
    """

    assert {:ok, module} = GeneratedParser.parse_source("Main.elm", source)

    project = %Project{
      project_dir: "/tmp",
      elm_json: %{},
      modules: [module],
      diagnostics: []
    }

    assert {:ok, ir} = Lowerer.lower_project(project)
    assert is_list(ir.diagnostics)
  end
end
