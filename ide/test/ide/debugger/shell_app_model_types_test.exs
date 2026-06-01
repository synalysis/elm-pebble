defmodule Ide.Debugger.ShellAppModelTypesTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.{RuntimeArtifacts, Surface}

  test "shell_map and app_model partition artifacts from model fields" do
    surface = %{
      model: %{
        "last_path" => "src/Main.elm",
        "last_source" => "module Main exposing (main)\nmain = 0",
        "runtime_model" => %{"count" => 1},
        "elm_introspect" => %{"module" => "Main"}
      }
    }

    normalized = RuntimeArtifacts.normalize_surface(surface)
    shell = RuntimeArtifacts.shell_map(normalized)
    app = Surface.app_model(Surface.from_map(normalized))

    assert shell["debugger_contract"] == %{"module" => "Main"}
    refute Map.has_key?(app, "elm_introspect")
    refute Map.has_key?(app, "debugger_contract")
    assert app["last_path"] == "src/Main.elm"
    assert app["runtime_model"] == %{"count" => 1}
  end

  test "Surface exposes typed app_model and shell" do
    surface =
      Surface.from_map(%{
        model: %{"last_path" => "src/Main.elm"},
        shell: %{"debugger_contract" => %{"module" => "Main"}}
      })

    assert surface.shell["debugger_contract"]["module"] == "Main"
    assert surface.model["last_path"] == "src/Main.elm"
  end
end
