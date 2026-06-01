defmodule Elmx.SimpleProjectCompileTest do
  use ExUnit.Case

  @project_dir Path.expand("fixtures/simple_project", __DIR__)

  test "compile_in_memory loads Main for simple_project" do
    revision = "simple-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, %Elmx.CompileResult{} = result} =
             Elmx.compile_in_memory(@project_dir, %{
               entry_module: "Main",
               revision: revision,
               strip_dead_code: true
             })

    assert is_atom(result.entry_module)
    assert function_exported?(result.entry_module, :init, 1)
    assert function_exported?(result.entry_module, :update, 2)
    assert function_exported?(result.entry_module, :view, 1)
    assert function_exported?(result.entry_module, :debugger_execute, 1)

    assert {:ok, payload} =
             Elmx.Runtime.Executor.execute_generated(result.entry_module, %{
               "current_model" => %{"launch_context" => %{}},
               "message" => nil
             })

    patch = payload[:model_patch] || payload["model_patch"]
    runtime_model = patch["runtime_model"] || patch[:runtime_model]
    assert Map.has_key?(runtime_model, "value") or Map.has_key?(runtime_model, :value)
  end
end
