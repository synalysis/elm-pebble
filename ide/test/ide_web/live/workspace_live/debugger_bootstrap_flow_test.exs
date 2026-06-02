defmodule IdeWeb.WorkspaceLive.DebuggerBootstrapFlowTest do
  use Ide.DataCase, async: false

  alias Ide.Compiler.Diagnostics
  alias Ide.Debugger.AgentStore
  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.Types.CompileIngestBridge
  alias Ide.Projects
  alias IdeWeb.WorkspaceLive.BuildFlow

  @tag timeout: 120_000
  test "ingesting warm compile before watch reload executes YES init with runtime model" do
    slug = "debugger-bootstrap-yes-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "YES Bootstrap",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "watchface-yes"
             })

    scope_key = Projects.scope_key(project)
    watch_profile_id = "aplite"

    assert {:ok, _} =
             Ide.Debugger.start_session(scope_key, %{watch_profile_id: watch_profile_id})

    assert {:ok, compile_results, _primary} =
             BuildFlow.warm_debugger_compile_context_work(project, skip_roots: ["phone"])

    assert {"watch", {:ok, watch_result}} = List.keyfind(compile_results, "watch", 0)
    assert watch_result.status == :ok

    watch_manifest =
      Map.get(watch_result, :elmx_manifest) || Map.get(watch_result, "elmx_manifest")

    assert watch_manifest["contract"] == "elmx.runtime_executor.v1"

    ingest_compile_results(scope_key, compile_results)

    state = AgentStore.fetch(scope_key)
    watch_execution = RuntimeArtifacts.execution_model(Map.get(state, :watch, %{}))
    assert RuntimeArtifacts.versioned_elmx_artifacts?(watch_execution)

    watch_main =
      project
      |> Projects.project_workspace_path()
      |> Path.join("watch/src/Main.elm")
      |> File.read!()

    assert {:ok, _} =
             Ide.Debugger.reload(scope_key, %{
               rel_path: "src/Main.elm",
               source: watch_main,
               reason: "debugger_bootstrap_test",
               source_root: "watch"
             })

    state = AgentStore.fetch(scope_key)
    runtime_model = get_in(state, [:watch, :model, "runtime_model"]) || %{}

    refute Map.get(runtime_model, "runtime_execution_error")
    assert Map.get(runtime_model, "screenW") == 144
    assert Map.has_key?(runtime_model, "displayShape")
    assert Map.has_key?(runtime_model, "wind") or Map.has_key?(runtime_model, "weather")
  end

  defp ingest_compile_results(scope_key, compile_results) do
    Enum.each(compile_results, fn
      {label, {:ok, result}} ->
        diagnostics = Map.get(result, :diagnostics, [])
        counts = Diagnostics.summary(diagnostics)

        attrs =
          result
          |> Map.put(:source_root, label)
          |> Map.put(:error_count, counts.error_count)
          |> Map.put(:warning_count, counts.warning_count)
          |> Map.put(:diagnostics, diagnostics)
          |> CompileIngestBridge.from_compiler_compile_result()

        {:ok, _} = Ide.Debugger.ingest_elmc_compile(scope_key, attrs)

      _ ->
        :ok
    end)
  end
end
