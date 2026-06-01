defmodule Elmx.ExecutorIntegrationTest do
  use ExUnit.Case

  @project_dir Path.expand("fixtures/simple_project", __DIR__)

  test "init and view on compiled simple_project Main" do
    revision = "exec-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, %Elmx.CompileResult{entry_module: module}} =
             Elmx.compile_in_memory(@project_dir, %{
               entry_module: "Main",
               revision: revision,
               strip_dead_code: true,
               mode: :ide_runtime
             })

    assert {:ok, init_payload} =
             Elmx.Runtime.Executor.execute_generated(module, %{
               "current_model" => %{"launch_context" => %{"launch_reason" => "LaunchSystem"}},
               "message" => nil
             })

    patch = init_payload[:model_patch] || init_payload["model_patch"]
    runtime_model = patch["runtime_model"] || patch[:runtime_model]
    assert is_map(runtime_model)
    assert runtime_model["value"] == 0

    view_tree = init_payload[:view_tree] || init_payload["view_tree"]
    type = view_tree["type"] || view_tree[:type]
    assert type == "windowStack" or type == :windowStack

    assert {:ok, step_payload} =
             Elmx.Runtime.Executor.execute_generated(module, %{
               "current_model" => %{"runtime_model" => runtime_model},
               "message" => "Increment",
               "message_value" => nil
             })

    step_patch = step_payload[:model_patch] || step_payload["model_patch"]
    stepped = step_patch["runtime_model"] || step_patch[:runtime_model]
    assert stepped["value"] == 1 or stepped[:value] == 1
  end
end
