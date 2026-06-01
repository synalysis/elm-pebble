defmodule ElmExecutor.InitRuntimeModelResolutionTest do
  use ExUnit.Case, async: true

  alias ElmExecutor.Runtime.SemanticExecutor
  alias ElmExecutor.Runtime.SemanticExecutor.RuntimeModelValues

  test "init does not keep parser-only init_model fields when Core IR init cannot run" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (..)\n",
      introspect: %{
        "module" => "Main",
        "init_model" => %{
          "screenW" => 144,
          "player" => %{"$call" => "Pokemon.playerFromSpecies", "$args" => []}
        }
      },
      current_model: %{
        "launch_context" => %{
          "screen" => %{"width" => 144, "height" => 168, "shape" => "Rectangular"},
          "reason" => "LaunchWakeup"
        }
      },
      current_view_tree: %{},
      message: nil,
      elm_executor_metadata: %{"entry_module" => "Main"}
    }

    assert {:ok, result} = SemanticExecutor.execute(request)
    runtime_model = result.model_patch["runtime_model"]

    refute Map.has_key?(runtime_model, "player")
    refute RuntimeModelValues.unresolved_model?(runtime_model)
  end
end
