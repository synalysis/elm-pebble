defmodule Ide.Debugger.RuntimeExecutorTest do
  use ExUnit.Case, async: false

  alias Ide.Debugger.CoreIRFixtures
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
  end

  test "legacy runtime mode is disabled" do
    Application.put_env(:ide, RuntimeExecutor,
      external_executor_module: ExternalOk,
      runtime_mode: :legacy
    )

    assert {:error, {:core_ir_execution_failed, :legacy_runtime_mode_disabled}} =
             RuntimeExecutor.execute(step_input())
  end

  test "returns error when external module is missing execute/1" do
    Application.put_env(:ide, RuntimeExecutor, external_executor_module: NoExecute)

    assert {:error, {:core_ir_execution_failed, {:external_executor_not_loaded, NoExecute}}} =
             RuntimeExecutor.execute(step_input())
  end

  test "returns error when external runtime errors" do
    Application.put_env(:ide, RuntimeExecutor, external_executor_module: ExternalError)

    assert {:error, {:core_ir_execution_failed, :boom}} = RuntimeExecutor.execute(step_input())
  end

  test "returns error on invalid external payload" do
    Application.put_env(:ide, RuntimeExecutor, external_executor_module: ExternalInvalid)

    assert {:error, {:core_ir_execution_failed, {:invalid_external_runtime_result, {:ok, :bad_payload}}}} =
             RuntimeExecutor.execute(step_input())
  end

  test "elmc adapter returns error when no candidate API exists" do
    Application.put_env(:ide, ElmcAdapter, candidates: [{NoExecute, :execute, 1}])
    Application.put_env(:ide, RuntimeExecutor, external_executor_module: ElmcAdapter)

    assert {:error, {:core_ir_execution_failed, {:elmc_runtime_unavailable, _candidates}}} =
             RuntimeExecutor.execute(step_input())
  end

  test "elmc adapter executes first available rich candidate contract" do
    Application.put_env(:ide, ElmcAdapter, candidates: [{ElmcCandidateRich, :execute, 1}])
    Application.put_env(:ide, RuntimeExecutor, external_executor_module: ElmcAdapter)

    assert {:ok, payload} = RuntimeExecutor.execute(step_input())
    assert payload.runtime["engine"] == "elmc_runtime_preview_v1"
    assert payload.model_patch["runtime_model"]["n"] == 7
  end

  test "elm_executor adapter requires versioned core ir" do
    Application.put_env(:ide, RuntimeExecutor, external_executor_module: ElmExecutorAdapter)

    assert {:error, {:core_ir_execution_failed, :missing_core_ir}} =
             RuntimeExecutor.execute(step_input())
  end

  test "elm_executor adapter executes runtime executor contract with core ir" do
    Application.put_env(:ide, RuntimeExecutor, external_executor_module: ElmExecutorAdapter)

    assert {:ok, payload} = RuntimeExecutor.execute(step_input(CoreIRFixtures.step_input_attrs()))
    assert payload.runtime["engine"] == "elm_executor_runtime_v1"
    assert payload.runtime["execution_backend"] == "external"
    assert payload.model_patch["runtime_model_source"] == "step_message"
  end

  test "elm_executor adapter can execute through compiled module when configured" do
    out_dir =
      Path.join(System.tmp_dir!(), "elm_executor_ide_rt_#{System.unique_integer([:positive])}")

    project_dir = Path.expand("../../../../elmc/test/fixtures/pebble_surface_project", __DIR__)

  case ElmExecutor.compile(project_dir, %{out_dir: out_dir, entry_module: "Main", strict_core_ir: false}) do
      {:ok, _} ->
        Application.put_env(:ide, ElmExecutorAdapter,
          compiled_out_dir: out_dir,
          compiled_entry_module: "Main"
        )

        Application.put_env(:ide, RuntimeExecutor, external_executor_module: ElmExecutorAdapter)

        assert {:ok, payload} =
                 RuntimeExecutor.execute(step_input(CoreIRFixtures.step_input_attrs()))

        assert payload.runtime["contract"] == "elm_executor.runtime_executor.v1"

      {:error, reason} ->
        flunk("fixture compile failed: #{inspect(reason)}")
    end
  end

  defp step_input(extra \\ %{}) when is_map(extra) do
    Map.merge(
      %{
        source_root: "watch",
        rel_path: "watch/src/Main.elm",
        source: "module Main exposing (main)\n",
        introspect: %{
          "msg_constructors" => ["Tick"],
          "update_case_branches" => ["Tick"],
          "view_case_branches" => [],
          "init_model" => %{"ticks" => 0},
          "view_tree" => %{"type" => "root", "children" => []}
        },
        current_model: %{"runtime_model" => %{"ticks" => 0}},
        current_view_tree: %{"type" => "root", "children" => []},
        message: "Tick 0",
        update_branches: ["Tick"]
      },
      extra
    )
  end
end
