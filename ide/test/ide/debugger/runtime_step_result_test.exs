defmodule Ide.Debugger.RuntimeStepResultTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.RuntimeExecutor

  test "execute returns a runtime step result shape" do
    revision = "runtime-step-result-#{System.unique_integer([:positive])}"
    workspace = Path.expand("../../../../elmx/test/fixtures/minimal", __DIR__)

    assert {:ok, %Elmx.CompileResult{} = compile_result} =
             Elmx.compile_in_memory(workspace, %{
               entry_module: "Main",
               revision: revision,
               mode: :ide_runtime
             })

    input = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{"module" => "Main"},
      current_model: %{"runtime_model" => %{}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: nil,
      elmx_manifest: compile_result.manifest,
      elmx_revision: revision
    }

    assert {:ok, result} = RuntimeExecutor.execute(input)
    assert is_map(result.model_patch)
    assert is_list(result.view_output)
    assert is_map(result.runtime)
    assert is_list(result.protocol_events)
    assert is_list(result.followup_messages)
  end
end
