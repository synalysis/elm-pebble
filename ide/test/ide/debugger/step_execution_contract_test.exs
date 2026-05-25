defmodule Ide.Debugger.StepExecutionContractTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.{StepInput, Surface}
  alias Ide.Debugger.Types.StepExecutionContract

  test "request_from builds executor request for watch surface" do
    surface =
      Surface.from_map(%{
        model: %{"last_path" => "src/Main.elm"},
        shell: %{"elm_introspect" => %{"module" => "Main"}}
      })

    step = StepInput.from_surface(:watch, surface, "Tick")
    request = StepExecutionContract.request_from(step)

    assert request.source_root == "watch"
    assert request.message == "Tick"
    assert request.introspect["module"] == "Main"
  end

  test "step_result_from_wire normalizes string-key executor maps" do
    wire = %{
      "model_patch" => %{"runtime_model" => %{"n" => 2}},
      "view_output" => [],
      "runtime" => %{},
      "protocol_events" => [],
      "followup_messages" => []
    }

    assert %{model_patch: %{"runtime_model" => %{"n" => 2}}} =
             StepExecutionContract.step_result_from_wire(wire)
  end

  test "merge_model_patch applies string and atom keys" do
    model = %{"runtime_model" => %{"n" => 0}}
    patch = %{"runtime_model" => %{"n" => 1}, :runtime_last_message => "Tick"}

    merged = StepExecutionContract.merge_model_patch(model, patch)

    assert get_in(merged, ["runtime_model", "n"]) == 1
    assert merged["runtime_last_message"] == "Tick"
  end

  test "step_result_from_local_fallback matches companion phone source in request path" do
    surface = Surface.from_map(%{model: %{}, shell: %{"elm_introspect" => %{"module" => "Main"}}})
    step = StepInput.from_surface(:companion, surface, "Back")

    assert StepExecutionContract.request_from(step).source_root == "phone"

    assert %{view_tree: %{}, view_output: []} =
             StepExecutionContract.step_result_from_local_fallback(%{"runtime_model" => %{}}, %{})
  end
end
