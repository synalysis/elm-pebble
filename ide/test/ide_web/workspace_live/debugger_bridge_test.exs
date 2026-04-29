defmodule IdeWeb.WorkspaceLive.DebuggerBridgeTest do
  use Ide.DataCase, async: false

  alias Ide.Projects
  alias Ide.Debugger
  alias IdeWeb.WorkspaceLive.DebuggerBridge

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "ide_debugger_bridge_test_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:ide, Ide.Projects, projects_root: root)
    on_exit(fn -> File.rm_rf(root) end)
    :ok
  end

  test "sync_check counts atom and string severities consistently" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "BridgeCheck",
               "slug" => "bridge-check",
               "target_type" => "app"
             })

    assert {:ok, _} = Debugger.start_session(project.slug)

    socket = debugger_socket(project)

    result = %{
      status: :ok,
      checked_path: ".",
      diagnostics: [
        %{severity: :error, message: "atom error", source: "elmc"},
        %{"severity" => "warning", "message" => "string warning", "source" => "elmc"}
      ]
    }

    _updated = DebuggerBridge.sync_check(socket, result)
    assert {:ok, state} = Debugger.snapshot(project.slug, event_limit: 5)
    event = Enum.find(state.events, &(&1.type == "debugger.elmc_check"))
    assert event.payload.error_count == 1
    assert event.payload.warning_count == 1

    assert [%{"message" => "atom error"}, %{"message" => "string warning"}] =
             event.payload.diagnostic_preview
  end

  test "sync_compile and sync_manifest tolerate nil diagnostics and keep counts aligned" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "BridgeCompileManifest",
               "slug" => "bridge-compile-manifest",
               "target_type" => "app"
             })

    assert {:ok, _} = Debugger.start_session(project.slug)

    socket = debugger_socket(project)

    _updated_compile =
      DebuggerBridge.sync_compile(socket, %{
        status: :ok,
        compiled_path: ".",
        revision: "rev-a",
        cached?: false,
        diagnostics: nil
      })

    _updated_manifest =
      DebuggerBridge.sync_manifest(socket, %{
        status: :ok,
        manifest_path: ".",
        revision: "rev-b",
        strict?: false,
        cached?: false,
        manifest: %{"schema_version" => 1},
        diagnostics: nil
      })

    assert {:ok, state} = Debugger.snapshot(project.slug, event_limit: 10)
    compile = Enum.find(state.events, &(&1.type == "debugger.elmc_compile"))
    manifest = Enum.find(state.events, &(&1.type == "debugger.elmc_manifest"))

    assert compile.payload.error_count == 0
    assert compile.payload.warning_count == 0
    assert compile.payload.diagnostic_preview == []

    assert manifest.payload.error_count == 0
    assert manifest.payload.warning_count == 0
    assert manifest.payload.diagnostic_preview == []
  end

  test "sync_compile assigns runtime artifacts to inferred source root" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "BridgeCompileArtifacts",
               "slug" => "bridge-compile-artifacts",
               "target_type" => "app"
             })

    assert {:ok, _} = Debugger.start_session(project.slug)

    socket = debugger_socket(project)
    workspace = Projects.project_workspace_path(project)
    core_ir = %{"modules" => [%{"name" => "CompanionApp"}]}

    _updated_compile =
      DebuggerBridge.sync_compile(socket, %{
        status: :ok,
        compiled_path: Path.join([workspace, "phone", ".elmc-build"]),
        revision: "rev-phone",
        cached?: false,
        diagnostics: nil,
        elm_executor_core_ir_b64: :erlang.term_to_binary(core_ir) |> Base.encode64(),
        elm_executor_metadata: %{"target" => "phone"}
      })

    assert {:ok, state} = Debugger.snapshot(project.slug, event_limit: 10)
    assert get_in(state.companion, [:model, "elm_executor_core_ir_b64"])
    refute get_in(state.watch, [:model, "elm_executor_core_ir_b64"])
  end

  defp debugger_socket(project) do
    %Phoenix.LiveView.Socket{}
    |> Phoenix.Component.assign(:project, project)
    |> Phoenix.Component.assign(:debugger_state, %{running: true})
    |> Phoenix.Component.assign(:debugger_event_limit, 30)
  end
end
