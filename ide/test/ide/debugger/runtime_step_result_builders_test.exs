defmodule Ide.Debugger.RuntimeStepResultBuildersTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.RuntimeExecutor.ResultNormalizer
  alias Ide.Debugger.Types.RuntimeStepResult

  test "from_executor_result matches normalize_step_result" do
    raw = %{
      model_patch: %{"runtime_model" => %{"n" => 1}},
      view_tree: %{"tag" => "root"},
      view_output: [%{"tag" => "Text"}],
      runtime: %{"engine" => "test"},
      protocol_events: [%{"type" => "tx"}],
      followup_messages: ["Tick"]
    }

    normalized = ResultNormalizer.normalize_step_result(raw)
    assert RuntimeStepResult.from_executor_result(raw) == normalized
  end

  test "from_executor_wire accepts string-key executor maps" do
    wire = %{
      "model_patch" => %{"runtime_model" => %{}},
      "view_output" => [],
      "runtime" => %{},
      "protocol_events" => [],
      "followup_messages" => []
    }

    assert %{model_patch: %{}, view_output: []} = RuntimeStepResult.from_executor_wire(wire)
  end

  test "from_local_fallback builds minimal step shape" do
    assert %{model_patch: %{"x" => 1}, view_tree: %{}, view_output: []} =
             RuntimeStepResult.from_local_fallback(%{"x" => 1}, %{})
  end
end
