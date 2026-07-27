defmodule Elmc.FrontendBridgeTest do
  use ExUnit.Case

  alias ElmEx.Frontend.Bridge

  test "load_project extracts modules and imports" do
    project_dir = Path.expand("fixtures/simple_project", __DIR__)

    assert {:ok, project} = Bridge.load_project(project_dir)
    assert is_list(project.modules)
    assert Enum.any?(project.modules, &(&1.name == "Main"))

    main = Enum.find(project.modules, &(&1.name == "Main"))
    assert "List" in main.imports
    assert "Maybe" in main.imports
  end
end
