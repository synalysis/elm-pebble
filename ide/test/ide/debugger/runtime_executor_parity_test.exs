defmodule Ide.Debugger.RuntimeExecutorParityTest do
  use ExUnit.Case, async: false

  alias Ide.Debugger.RuntimeExecutor
  alias Ide.Debugger.RuntimeExecutor.ElmExecutorAdapter
  alias Ide.Debugger.RuntimeExecutor.ElmcAdapter

  setup do
    old = Application.get_env(:ide, RuntimeExecutor, [])

    on_exit(fn ->
      Application.put_env(:ide, RuntimeExecutor, old)
    end)

    :ok
  end

  test "elm_executor adapter preserves protocol/view parity while exposing strict model divergence" do
    Application.put_env(:ide, RuntimeExecutor, external_executor_module: ElmcAdapter)
    assert {:ok, elmc_payload} = RuntimeExecutor.execute(step_input())

    Application.put_env(:ide, RuntimeExecutor, external_executor_module: ElmExecutorAdapter)
    assert {:ok, elm_executor_payload} = RuntimeExecutor.execute(step_input())

    assert elm_executor_payload.model_patch["runtime_model"]["n"] == 0
    assert elmc_payload.model_patch["runtime_model"]["n"] == 1
    assert elm_executor_payload.model_patch["runtime_model"]["last_operation"] == "nil"
    assert elmc_payload.model_patch["runtime_model"]["last_operation"] == "inc"

    assert strip_runtime_step_counts(elm_executor_payload.view_tree) ==
             strip_runtime_step_counts(elmc_payload.view_tree)

    assert elm_executor_payload.view_output == elmc_payload.view_output
    assert elm_executor_payload.runtime["operation_source"] == "unmapped_message"
    assert is_nil(elmc_payload.runtime["operation_source"])
  end

  test "elm_executor adapter preserves absence of synthetic protocol events for phone surface steps" do
    Application.put_env(:ide, RuntimeExecutor, external_executor_module: ElmcAdapter)
    assert {:ok, elmc_payload} = RuntimeExecutor.execute(step_input("phone"))

    Application.put_env(:ide, RuntimeExecutor, external_executor_module: ElmExecutorAdapter)
    assert {:ok, elm_executor_payload} = RuntimeExecutor.execute(step_input("phone"))

    assert elm_executor_payload.model_patch["runtime_model"]["n"] == 0
    assert elmc_payload.model_patch["runtime_model"]["n"] == 1
    assert elm_executor_payload.protocol_events == []
    assert elmc_payload.protocol_events == []
  end

  defp step_input(source_root \\ "watch") do
    %{
      source_root: source_root,
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "msg_constructors" => ["Inc"],
        "update_case_branches" => ["Inc"],
        "view_case_branches" => [],
        "init_model" => %{"n" => 0},
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"n" => 0}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Inc",
      update_branches: ["Inc"]
    }
  end

  defp strip_runtime_step_counts(tree) when is_map(tree) do
    tree
    |> Map.delete("model_entries")
    |> Map.delete("op")
    |> Map.delete("last_runtime_step_op")
    |> Map.update("children", [], fn children ->
      children
      |> List.wrap()
      |> Enum.map(&strip_runtime_step_counts/1)
    end)
  end

  defp strip_runtime_step_counts(other), do: other
end
