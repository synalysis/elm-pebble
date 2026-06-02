defmodule Ide.Debugger.RuntimeExecutor.ResultNormalizerTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.RuntimeExecutor.ResultNormalizer

  test "normalize maps executor wire keys to execution_result" do
    wire = %{
      "model_patch" => %{"runtime_model" => %{"n" => 1}},
      "view_tree" => %{"type" => "root"},
      "view_output" => [%{"kind" => "text_label"}],
      "runtime" => %{"engine" => "elmx_runtime_v1"},
      "protocol_events" => [%{"type" => "debugger.protocol_tx"}],
      "followup_messages" => [%{"message" => "Tick"}]
    }

    result = ResultNormalizer.normalize(wire)

    assert result.model_patch["runtime_model"]["n"] == 1
    assert result.view_tree["type"] == "root"
    assert length(result.view_output) == 1
    assert result.runtime["engine"] == "elmx_runtime_v1"
    assert length(result.protocol_events) == 1
    assert hd(result.followup_messages)["message"] == "Tick"
  end

  test "normalize_step_result aligns execution_result with RuntimeStepResult" do
    execution = %{
      model_patch: %{"x" => 1},
      view_tree: nil,
      view_output: [],
      runtime: %{"engine" => "test"},
      protocol_events: [],
      followup_messages: []
    }

    step = ResultNormalizer.normalize_step_result(execution)

    assert step.model_patch == execution.model_patch
    assert step.runtime == execution.runtime
    assert step.view_tree == nil
  end

  test "normalize_elmc_loose maps runtime_model wire shape" do
    input = %{source_root: "watch", rel_path: "src/Main.elm"}

    result =
      ResultNormalizer.normalize_elmc_loose(
        %{
          "runtime_model" => %{"n" => 3},
          "view_tree" => %{"type" => "root"},
          "runtime" => %{"engine" => "elmc_runtime_loose_v1"},
          "view_output" => [%{"kind" => "clear"}]
        },
        input
      )

    assert result.model_patch["runtime_model"]["n"] == 3
    assert result.runtime["engine"] == "elmc_runtime_loose_v1"
    assert result.runtime["source_root"] == "watch"
  end

  test "annotate_backend stamps execution_backend on runtime and model_patch" do
    base = %{
      model_patch: %{"runtime_model" => %{}},
      view_tree: nil,
      view_output: [],
      runtime: %{"engine" => "elmx_runtime_v1"},
      protocol_events: [],
      followup_messages: []
    }

    annotated = ResultNormalizer.annotate_backend(base, "external", :boom)

    assert annotated.runtime["execution_backend"] == "external"
    assert annotated.model_patch["runtime_execution"]["execution_backend"] == "external"
    assert String.contains?(annotated.runtime["external_fallback_reason"], "boom")
  end
end
