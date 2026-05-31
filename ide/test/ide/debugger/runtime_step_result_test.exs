defmodule Ide.Debugger.RuntimeStepResultTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.{CoreIRFixtures, RuntimeExecutor}

  test "execute returns a runtime step result shape" do
    input =
      Map.merge(
        %{
          source_root: "watch",
          rel_path: "watch/src/Main.elm",
          source: "module Main exposing (main)\n",
          introspect: %{
            "module" => "Main",
            "init_model" => %{"ticks" => 0},
            "view_tree" => %{"type" => "root", "children" => []}
          },
          current_model: %{"runtime_model" => %{"ticks" => 0}},
          current_view_tree: %{"type" => "root", "children" => []},
          message: nil
        },
        CoreIRFixtures.step_input_attrs()
      )

    assert {:ok, result} = RuntimeExecutor.execute(input)
    assert is_map(result.model_patch)
    assert is_list(result.view_output)
    assert is_map(result.runtime)
    assert is_list(result.protocol_events)
    assert is_list(result.followup_messages)
  end
end
