defmodule Ide.Debugger.RuntimeStepResultTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.RuntimeExecutor

  test "execute returns a runtime step result shape" do
    input = %{
      source_root: "watch",
      rel_path: "src/Main.elm",
      source: "",
      introspect: %{"module" => "Main", "init_model" => %{}},
      current_model: %{},
      current_view_tree: %{},
      message: nil
    }

    assert {:ok, result} = RuntimeExecutor.execute(input)
    assert is_map(result.model_patch)
    assert is_list(result.view_output)
    assert is_map(result.runtime)
    assert is_list(result.protocol_events)
    assert is_list(result.followup_messages)
  end
end
