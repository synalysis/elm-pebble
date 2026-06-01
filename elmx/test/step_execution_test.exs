defmodule Elmx.StepExecutionTest do
  use ExUnit.Case

  @project_dir Path.expand("fixtures/simple_project", __DIR__)

  test "update handles Increment after init" do
    revision = "step-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, %{entry_module: module}} =
             Elmx.compile_in_memory(@project_dir, %{
               revision: revision,
               strip_dead_code: true,
               mode: :ide_runtime
             })

    assert {:ok, init_payload} =
             Elmx.Runtime.Executor.execute_generated(module, %{
               "current_model" => %{"launch_context" => %{}},
               "message" => nil
             })

    init_model = get_in(init_payload, [:model_patch, "runtime_model"]) ||
                   get_in(init_payload, ["model_patch", "runtime_model"])

    assert {:ok, step_payload} =
             Elmx.Runtime.Executor.execute_generated(module, %{
               "current_model" => %{"runtime_model" => init_model},
               "message" => "Increment"
             })

    stepped = get_in(step_payload, [:model_patch, "runtime_model"]) ||
                get_in(step_payload, ["model_patch", "runtime_model"])

    assert stepped != init_model
  end
end
