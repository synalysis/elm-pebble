defmodule IdeWeb.WorkspaceLive.DebuggerBootstrapFlowTest do
  use Ide.DataCase, async: false

  alias Ide.Compiler.Diagnostics
  alias Ide.Debugger.AgentStore
  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.Types.CompileIngestBridge
  alias Ide.Projects
  alias IdeWeb.WorkspaceLive.BuildFlow
  alias IdeWeb.WorkspaceLive.DebuggerBootstrapFlow
  alias IdeWeb.WorkspaceLive.DebuggerPage.ModelMetadata

  @tag timeout: 180_000
  test "companion bootstrap does not re-init watch and populates companion model" do
    slug = "tangram-companion-bootstrap-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Tangram Bootstrap",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "watchface-tangram-time"
             })

    scope_key = Projects.scope_key(project)

    assert {:ok, _} =
             Ide.Debugger.start_session(scope_key, %{watch_profile_id: "basalt"})

    assert {:ok, compile_results, _primary} =
             BuildFlow.warm_debugger_compile_context_work(project, skip_roots: ["phone"])

    ingest_compile_results(scope_key, compile_results)

    watch_main =
      project
      |> Projects.project_workspace_path()
      |> Path.join("watch/src/Main.elm")
      |> File.read!()

    assert {:ok, _} =
             Ide.Debugger.reload(scope_key, %{
               rel_path: "src/Main.elm",
               source: watch_main,
               reason: "debugger_bootstrap",
               source_root: "watch"
             })

    assert {:ok, _} =
             DebuggerBootstrapFlow.run_companion_bootstrap(project, force_sync: true)

    assert wait_until_companion_bootstrapped(scope_key)

    {:ok, snap} = Ide.Debugger.snapshot(scope_key, event_limit: 500)

    watch_init_count =
      (snap.debugger_timeline || [])
      |> Enum.count(fn row -> row.target == "watch" and row.type == "init" end)

    assert watch_init_count == 1
    assert DebuggerBootstrapFlow.companion_bootstrapped?(snap)

    public_companion = ModelMetadata.public_model(Map.get(snap, :companion))
    assert Map.has_key?(public_companion, "figure")

    public_watch = ModelMetadata.public_model(Map.get(snap, :watch))
    assert %{"ctor" => "Just", "args" => [0]} = Map.get(public_watch, "companionFigure")
  end

  @tag timeout: 180_000
  test "async companion bootstrap completes deferred init before returning" do
    slug = "tangram-async-companion-bootstrap-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Tangram Async",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "watchface-tangram-time"
             })

    scope_key = Projects.scope_key(project)

    assert {:ok, _} =
             Ide.Debugger.start_session(scope_key, %{watch_profile_id: "basalt"})

    assert {:ok, compile_results, _primary} =
             BuildFlow.warm_debugger_compile_context_work(project, skip_roots: ["phone"])

    ingest_compile_results(scope_key, compile_results)

    watch_main =
      project
      |> Projects.project_workspace_path()
      |> Path.join("watch/src/Main.elm")
      |> File.read!()

    assert {:ok, _} =
             Ide.Debugger.reload(scope_key, %{
               rel_path: "src/Main.elm",
               source: watch_main,
               reason: "debugger_bootstrap",
               source_root: "watch"
             })

    assert {:ok, _} = DebuggerBootstrapFlow.run_companion_bootstrap(project)

    state = AgentStore.fetch(scope_key)
    assert DebuggerBootstrapFlow.companion_bootstrapped?(state)

    public_watch = ModelMetadata.public_model(Map.get(state, :watch))
    assert %{"ctor" => "Just", "args" => [0]} = Map.get(public_watch, "companionFigure")
  end

  @tag timeout: 120_000
  test "watch-only analog project skips companion bootstrap without phone root error" do
    slug = "debugger-bootstrap-analog-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Analog Bootstrap",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "watchface-analog"
             })

    refute Projects.companion_app_present?(project)

    assert {:ok, %{phone_compile: :skipped, reload: :skipped}} =
             DebuggerBootstrapFlow.run_companion_bootstrap(project, force_sync: true)

    scope_key = Projects.scope_key(project)

    assert {:ok, _result} =
             DebuggerBootstrapFlow.run(project,
               watch_profile_id: "basalt",
               progress: fn _ -> :ok end
             )

    state = AgentStore.fetch(scope_key)
    refute DebuggerBootstrapFlow.companion_bootstrapped?(state)
    assert DebuggerBootstrapFlow.watch_surface_bootstrapped?(state)
  end

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

  defp wait_until_companion_bootstrapped(scope_key, attempts \\ 100) do
    state = AgentStore.fetch(scope_key)

    if DebuggerBootstrapFlow.companion_bootstrapped?(state) do
      true
    else
      if attempts > 0 do
        Process.sleep(100)
        wait_until_companion_bootstrapped(scope_key, attempts - 1)
      else
        flunk("companion bootstrap did not finish: #{inspect(state, limit: 5)}")
      end
    end
  end
end
