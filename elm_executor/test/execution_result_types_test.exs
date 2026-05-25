defmodule ElmExecutor.Runtime.ExecutionResultTypesTest do
  use ExUnit.Case, async: true

  alias ElmEx.CoreIR
  alias ElmExecutor.Runtime.SemanticExecutor
  test "execute returns execution result map with model_patch and runtime engine" do
    ir = %ElmEx.IR{
      modules: [
        %ElmEx.IR.Module{
          name: "Main",
          imports: [],
          declarations: [
            %ElmEx.IR.Declaration{
              kind: :function,
              name: "init",
              args: [],
              expr: %{op: :int_literal, value: 0},
              ownership: []
            },
            %ElmEx.IR.Declaration{
              kind: :function,
              name: "view",
              args: ["model"],
              expr: %{op: :int_literal, value: 1},
              ownership: []
            }
          ]
        }
      ]
    }

    assert {:ok, core_ir} = CoreIR.from_ir(ir)

    request = %{
      source_root: "watch",
      rel_path: "src/Main.elm",
      source: "module Main exposing (..)\n",
      introspect: %{
        "module" => "Main",
        "init_model" => %{"count" => 0},
        "msg_constructors" => [],
        "update_case_branches" => [],
        "view_tree" => %{}
      },
      current_model: %{"runtime_model" => %{}},
      current_view_tree: %{},
      elm_executor_core_ir: core_ir,
      elm_executor_metadata: %{}
    }

    assert {:ok, result} = SemanticExecutor.execute(request)
    assert match?(%{model_patch: %{}, runtime: %{}}, result)
    assert get_in(result, [:runtime, "engine"]) == "elm_executor_runtime_v1"
    assert is_list(result.protocol_events)
    assert is_list(result.followup_messages)
    assert is_map(result.model_patch)
    assert Map.has_key?(result, :runtime)
    assert is_map(result)
  end
end
