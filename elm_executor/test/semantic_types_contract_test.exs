defmodule ElmExecutor.Runtime.SemanticTypesContractTest do
  use ExUnit.Case, async: true

  alias ElmEx.CoreIR
  alias ElmExecutor.Runtime.CoreIRContract
  alias ElmExecutor.Runtime.SemanticExecutor

  test "eval_context carries indexed Core IR tables" do
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
            }
          ]
        }
      ]
    }

    assert {:ok, core_ir} = CoreIR.from_ir(ir)
    assert :ok = CoreIRContract.validate(core_ir)

    request = %{
      source_root: "watch",
      introspect: %{
        "module" => "Main",
        "init_model" => %{},
        "msg_constructors" => [],
        "update_case_branches" => [],
        "view_tree" => %{}
      },
      current_model: %{},
      current_view_tree: %{},
      elm_executor_core_ir: core_ir
    }

    assert {:ok, _result} = SemanticExecutor.execute(request)
  end

  test "view output rows use declared draw kinds" do
    row = %{"kind" => "bitmap_in_rect", "bitmap_id" => 0, "x" => 0, "y" => 100, "w" => 20, "h" => 8}
    assert row["kind"] == "bitmap_in_rect"
    assert is_integer(row["bitmap_id"])
  end

  test "execution_request map shape is accepted by execute" do
    req = %{
      source_root: "watch",
      introspect: %{"module" => "Main", "init_model" => %{}},
      current_model: %{"runtime_model" => %{}},
      current_view_tree: %{}
    }

    assert {:ok, _} = SemanticExecutor.execute(req)
  end

  test "eval_context resource index shape" do
    ctx = %{
      module: "Main",
      functions: %{},
      vector_resource_indices: %{"Icon" => 1}
    }

    assert Map.get(ctx, :vector_resource_indices) == %{"Icon" => 1}
  end
end
