defmodule Elmx.MainProgramTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.MainProgram
  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.Lowerer

  @project_dir Path.expand("fixtures/simple_project", __DIR__)

  test "worker_field_names come from main Platform.application record in IR" do
    {:ok, project} = Bridge.load_project(@project_dir)
    {:ok, ir} = Lowerer.lower_project(project)

    assert Enum.sort(MainProgram.worker_field_names(ir, "Main")) ==
             ["init", "subscriptions", "update", "view"]
  end

  test "dead_code_roots include main and worker fields from IR" do
    {:ok, project} = Bridge.load_project(@project_dir)
    {:ok, ir} = Lowerer.lower_project(project)

    assert "main" in MainProgram.dead_code_roots(ir, "Main")
    assert "init" in MainProgram.dead_code_roots(ir, "Main")
    assert "update" in MainProgram.dead_code_roots(ir, "Main")
  end
end
