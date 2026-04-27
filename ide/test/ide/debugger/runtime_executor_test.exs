defmodule Ide.Debugger.RuntimeExecutorTest do
  use ExUnit.Case, async: false

  alias Ide.Debugger.RuntimeExecutor
  alias Ide.Debugger.RuntimeExecutor.ElmExecutorAdapter
  alias Ide.Debugger.RuntimeExecutor.ElmcAdapter

  defmodule ExternalOk do
    @behaviour RuntimeExecutor

    @impl true
    def execute(_input) do
      {:ok,
       %{
         model_patch: %{
           "runtime_model" => %{"from_external" => true},
           "elm_executor_mode" => "runtime_executed",
           "elm_executor" => %{"engine" => "external_runtime_v1"}
         },
         view_tree: %{"type" => "external", "children" => []},
         view_output: [%{"kind" => "clear", "color" => 0}],
         runtime: %{"engine" => "external_runtime_v1"},
         protocol_events: [%{type: "debugger.protocol_tx", payload: %{message: "external"}}],
         followup_messages: [%{"message" => "Followup"}]
       }}
    end
  end

  defmodule ExternalError do
    @behaviour RuntimeExecutor

    @impl true
    def execute(_input), do: {:error, :boom}
  end

  defmodule ExternalInvalid do
    @behaviour RuntimeExecutor

    @impl true
    def execute(_input), do: {:ok, :bad_payload}
  end

  defmodule NoExecute do
  end

  defmodule ElmcCandidateRich do
    def execute(_request) do
      {:ok,
       %{
         model_patch: %{
           "runtime_model" => %{"n" => 7},
           "runtime_model_source" => "elmc_runtime",
           "elm_executor_mode" => "runtime_executed",
           "elm_executor" => %{"engine" => "elmc_runtime_preview_v1"}
         },
         view_tree: %{"type" => "elmc-root", "children" => []},
         view_output: [%{"kind" => "text_label", "x" => 1, "y" => 2, "text" => "ok"}],
         runtime: %{"engine" => "elmc_runtime_preview_v1"},
         protocol_events: [%{type: "debugger.protocol_tx", payload: %{message: "elmc"}}],
         followup_messages: [%{"message" => "ElmcFollowup"}]
       }}
    end
  end

  defmodule ElmcCandidateLoose do
    def run(_request) do
      {:ok,
       %{
         runtime_model: %{"n" => 11},
         view_tree: %{"type" => "elmc-loose", "children" => []},
         runtime: %{"engine" => "elmc_runtime_loose_v1"},
         view_output: "invalid"
       }}
    end
  end

  defmodule ElmcCandidateContextEcho do
    def execute(request) do
      core_ir = Map.get(request, :elm_executor_core_ir)
      metadata = Map.get(request, :elm_executor_metadata)

      {:ok,
       %{
         runtime_model: %{
           "has_core_ir" => is_map(core_ir),
           "has_metadata" => is_map(metadata),
           "metadata_mode" => if(is_map(metadata), do: Map.get(metadata, "mode"), else: nil)
         },
         view_tree: %{"type" => "ctx", "children" => []},
         runtime: %{"engine" => "elmc_ctx_echo"}
       }}
    end
  end

  setup do
    old = Application.get_env(:ide, RuntimeExecutor, [])
    old_adapter = Application.get_env(:ide, ElmcAdapter, [])
    old_elm_executor_adapter = Application.get_env(:ide, ElmExecutorAdapter, [])

    on_exit(fn ->
      Application.put_env(:ide, RuntimeExecutor, old)
      Application.put_env(:ide, ElmcAdapter, old_adapter)
      Application.put_env(:ide, ElmExecutorAdapter, old_elm_executor_adapter)
    end)

    :ok
  end

  test "uses external runtime executor when configured and valid" do
    Application.put_env(:ide, RuntimeExecutor, external_executor_module: ExternalOk)

    assert {:ok, payload} = RuntimeExecutor.execute(step_input())
    assert payload.runtime["engine"] == "external_runtime_v1"
    assert payload.runtime["execution_backend"] == "external"
    assert payload.model_patch["runtime_model"]["from_external"] == true
    assert payload.view_output == [%{"kind" => "clear", "color" => 0}]
    assert is_list(payload.protocol_events)
    assert payload.followup_messages == [%{"message" => "Followup"}]
    assert hd(payload.protocol_events).type == "debugger.protocol_tx"
  end

  test "legacy runtime mode bypasses external executors and uses deterministic seam" do
    Application.put_env(:ide, RuntimeExecutor,
      external_executor_module: ExternalOk,
      runtime_mode: :legacy
    )

    assert {:ok, payload} = RuntimeExecutor.execute(step_input())
    assert payload.runtime["engine"] == "elm_introspect_runtime_v1"
    assert payload.runtime["execution_backend"] == "legacy_default"
    assert payload.runtime["runtime_mode"] == "legacy"
  end

  test "falls back to deterministic seam when external module is missing execute/1" do
    Application.put_env(:ide, RuntimeExecutor, external_executor_module: NoExecute)

    assert {:ok, payload} = RuntimeExecutor.execute(step_input())
    assert payload.runtime["engine"] == "elm_introspect_runtime_v1"
    assert payload.runtime["execution_backend"] == "default"
    assert payload.model_patch["runtime_model_source"] == "step_message"
  end

  test "falls back to deterministic seam when external runtime errors in non-strict mode" do
    Application.put_env(:ide, RuntimeExecutor, external_executor_module: ExternalError)

    assert {:ok, payload} = RuntimeExecutor.execute(step_input())
    assert payload.runtime["engine"] == "elm_introspect_runtime_v1"
    assert payload.runtime["execution_backend"] == "fallback_default"
    assert is_binary(payload.runtime["external_fallback_reason"])

    assert String.contains?(
             payload.runtime["external_fallback_reason"],
             "external_runtime_executor_failed"
           )

    assert payload.model_patch["runtime_model_source"] == "step_message"
  end

  test "returns error when external runtime errors in strict mode" do
    Application.put_env(:ide, RuntimeExecutor,
      external_executor_module: ExternalError,
      external_executor_strict: true
    )

    assert {:error, {:external_runtime_executor_failed, :boom}} =
             RuntimeExecutor.execute(step_input())
  end

  test "returns error on invalid external payload in strict mode" do
    Application.put_env(:ide, RuntimeExecutor,
      external_executor_module: ExternalInvalid,
      external_executor_strict: true
    )

    assert {:error, {:invalid_external_runtime_result, :payload_not_map}} =
             RuntimeExecutor.execute(step_input())
  end

  test "elmc adapter falls back when no candidate API exists in non-strict mode" do
    Application.put_env(:ide, ElmcAdapter, candidates: [{NoExecute, :execute, 1}])
    Application.put_env(:ide, RuntimeExecutor, external_executor_module: ElmcAdapter)

    assert {:ok, payload} = RuntimeExecutor.execute(step_input())
    assert payload.runtime["engine"] == "elm_introspect_runtime_v1"
    assert payload.runtime["execution_backend"] == "fallback_default"
    assert payload.model_patch["runtime_model_source"] == "step_message"
  end

  test "elmc adapter returns strict error when no candidate API exists" do
    Application.put_env(:ide, ElmcAdapter, candidates: [{NoExecute, :execute, 1}])

    Application.put_env(:ide, RuntimeExecutor,
      external_executor_module: ElmcAdapter,
      external_executor_strict: true
    )

    assert {:error, {:external_runtime_executor_failed, {:elmc_runtime_unavailable, _candidates}}} =
             RuntimeExecutor.execute(step_input())
  end

  test "elmc adapter executes first available rich candidate contract" do
    Application.put_env(:ide, ElmcAdapter, candidates: [{ElmcCandidateRich, :execute, 1}])
    Application.put_env(:ide, RuntimeExecutor, external_executor_module: ElmcAdapter)

    assert {:ok, payload} = RuntimeExecutor.execute(step_input())
    assert payload.runtime["engine"] == "elmc_runtime_preview_v1"
    assert payload.runtime["execution_backend"] == "external"
    assert payload.model_patch["runtime_model"]["n"] == 7
    assert payload.view_output == [%{"kind" => "text_label", "x" => 1, "y" => 2, "text" => "ok"}]
    assert payload.followup_messages == [%{"message" => "ElmcFollowup"}]
    assert payload.model_patch["runtime_model_source"] == "elmc_runtime"
    assert hd(payload.protocol_events).type == "debugger.protocol_tx"
  end

  test "elmc adapter normalizes loose runtime_model response shape" do
    Application.put_env(:ide, ElmcAdapter, candidates: [{ElmcCandidateLoose, :run, 1}])
    Application.put_env(:ide, RuntimeExecutor, external_executor_module: ElmcAdapter)

    assert {:ok, payload} = RuntimeExecutor.execute(step_input())
    assert payload.runtime["engine"] == "elmc_runtime_loose_v1"
    assert payload.runtime["execution_backend"] == "external"
    assert payload.model_patch["runtime_model"]["n"] == 11
    assert payload.view_output == []
    assert payload.followup_messages == []
    assert payload.model_patch["runtime_model_source"] == "elmc_runtime"
  end

  test "elmc adapter can use default in-repo Elmc.Runtime.Executor candidate" do
    Application.put_env(:ide, ElmcAdapter, [])
    Application.put_env(:ide, RuntimeExecutor, external_executor_module: ElmcAdapter)

    assert {:ok, payload} = RuntimeExecutor.execute(step_input())
    assert payload.runtime["engine"] == "elmc_runtime_executor_v0"
    assert payload.runtime["execution_backend"] == "external"
    assert payload.model_patch["runtime_model_source"] == "step_message"
    assert is_binary(payload.runtime["runtime_model_sha256"])
  end

  test "elm_executor adapter executes runtime executor contract" do
    Application.put_env(:ide, RuntimeExecutor, external_executor_module: ElmExecutorAdapter)

    assert {:ok, payload} = RuntimeExecutor.execute(step_input())
    assert payload.runtime["engine"] == "elm_executor_runtime_v1"
    assert payload.runtime["execution_backend"] == "external"
    assert payload.runtime["compiler"] == "elm_executor"
    assert payload.model_patch["runtime_model_source"] == "step_message"
  end

  test "elm_executor adapter forwards optional metadata into runtime annotation" do
    Application.put_env(:ide, RuntimeExecutor, external_executor_module: ElmExecutorAdapter)

    input =
      step_input()
      |> Map.put(:elm_executor_core_ir, %{modules: []})
      |> Map.put(:elm_executor_metadata, %{
        "mode" => "debugger_test",
        "compiler" => "elm_executor"
      })

    assert {:ok, payload} = RuntimeExecutor.execute(input)
    assert payload.runtime["mode"] == "debugger_test"
    assert payload.runtime["compiler"] == "elm_executor"
  end

  test "elmc adapter forwards optional compiler context fields" do
    Application.put_env(:ide, ElmcAdapter, candidates: [{ElmcCandidateContextEcho, :execute, 1}])
    Application.put_env(:ide, RuntimeExecutor, external_executor_module: ElmcAdapter)

    input =
      step_input()
      |> Map.put(:elm_executor_core_ir, %{modules: [%{"name" => "Main"}]})
      |> Map.put(:elm_executor_metadata, %{"mode" => "echo"})

    assert {:ok, payload} = RuntimeExecutor.execute(input)
    assert payload.runtime["engine"] == "elmc_ctx_echo"
    assert payload.model_patch["runtime_model"]["has_core_ir"] == true
    assert payload.model_patch["runtime_model"]["has_metadata"] == true
    assert payload.model_patch["runtime_model"]["metadata_mode"] == "echo"
  end

  test "elm_executor adapter can execute through compiled module when configured" do
    out_dir =
      Path.join(System.tmp_dir!(), "elm_executor_ide_rt_#{System.unique_integer([:positive])}")

    project_dir = Path.expand("../../../priv/pebble_app_template", __DIR__)

    assert {:ok, _result} =
             ElmExecutor.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    Application.put_env(:ide, ElmExecutorAdapter,
      compiled_out_dir: out_dir,
      compiled_entry_module: "Main"
    )

    Application.put_env(:ide, RuntimeExecutor, external_executor_module: ElmExecutorAdapter)

    assert {:ok, payload} = RuntimeExecutor.execute(step_input())
    assert payload.runtime["engine"] == "elm_executor_runtime_v1"
    assert payload.runtime["contract"] == "elm_executor.runtime_executor.v1"
    assert payload.runtime["execution_backend"] == "external"
  end

  defp step_input do
    %{
      source_root: "watch",
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
end
