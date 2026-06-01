defmodule ElmEx.Frontend.BridgeSourceOverridesTest do
  use ExUnit.Case

  alias ElmEx.Frontend.Bridge

  test "load_project_from_sources overlays module source" do
    project_dir = Path.expand("../../elmx/test/fixtures/minimal", __DIR__)

    {:ok, project} =
      Bridge.load_project_from_sources(project_dir, %{
        "src/Main.elm" => """
        module Main exposing (add)

        add : Int -> Int -> Int
        add a b =
            a + b + 1
        """
      })

    main = Enum.find(project.modules, &(&1.name == "Main"))
    assert main
    assert Enum.any?(main.declarations, &(&1.name == "add"))
  end
end
