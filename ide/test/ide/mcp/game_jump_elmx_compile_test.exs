defmodule Ide.Mcp.GameJumpElmxCompileTest do
  use Ide.DataCase, async: false

  @enabled? System.get_env("ELMX_TEMPLATE_CORPUS") in ["1", "true", "TRUE"]

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "game-jump-n-run compiles and executes init when corpus enabled" do
    if @enabled? do
      Application.put_env(:ide, Ide.Debugger.RuntimeExecutor, execution_backend: :compiled_elixir)
      _ = Application.ensure_all_started(:elmx)

      assert {:ok, %{project: project}} =
               Ide.Mcp.DebuggerTemplateCorpus.bootstrap_template("game-jump-n-run", cleanup: false)

      try do
        workspace =
          project
          |> Ide.Projects.project_workspace_path()
          |> Path.join("watch")

        revision = "corpus-jump-" <> Integer.to_string(:erlang.unique_integer([:positive]))

        assert {:ok, %{elmx_manifest: manifest, elmx_revision: ^revision}} =
                 Ide.Compiler.build_elmx_artifacts_in_memory(workspace,
                   revision: revision,
                   strip_dead_code: true
                 )

        assert manifest["contract"] == "elmx.runtime_executor.v1"
        assert Elmx.module_for_revision(revision)

        launch_context = Ide.Debugger.RuntimeSurfaces.launch_context_for("basalt", "LaunchUser")

        assert {:ok, payload} =
                 Ide.Debugger.RuntimeExecutor.execute(%{
                   elmx_manifest: manifest,
                   elmx_revision: revision,
                   current_model: %{"launch_context" => launch_context},
                   message: nil,
                   introspect: %{},
                   source: "",
                   source_root: "watch",
                   rel_path: "src/Main.elm",
                   current_view_tree: %{}
                 })

        patch = payload.model_patch || payload[:model_patch]
        runtime_model = patch["runtime_model"] || patch[:runtime_model]
        assert is_map(runtime_model)
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end
end
