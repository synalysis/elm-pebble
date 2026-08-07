defmodule Ide.Debugger.CompiledElixirPhoneBridgeFollowupsTest do
  use Ide.DataCase, async: false

  @moduletag :debugger_session

  alias Ide.Debugger.CompiledElixirCorpusHelpers, as: Corpus
  alias Ide.Mcp.DebuggerTemplateCorpus
  alias Ide.Projects

  @enabled? Corpus.corpus_enabled?()

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-websocket phone init leaves connecting status without bridge followups when enabled" do
    if @enabled? and "companion-demo-websocket" in DebuggerTemplateCorpus.template_keys() do
      Corpus.ensure_compiled_elixir_backend!()

      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template("companion-demo-websocket",
                 cleanup: false
               )

      try do
        phone_workspace =
          project |> Projects.project_workspace_path() |> Path.join("phone")

        revision =
          "corpus-ws-followups-" <> Integer.to_string(:erlang.unique_integer([:positive]))

        init_request = %{
          current_model: %{},
          message: nil,
          introspect: %{},
          source: "",
          source_root: "phone",
          rel_path: "src/CompanionApp.elm",
          current_view_tree: %{}
        }

        assert {:ok, %{elmx_manifest: manifest, elmx_revision: ^revision}} =
                 Ide.Compiler.build_elmx_artifacts_in_memory(phone_workspace,
                   revision: revision,
                   entry_module: "CompanionApp"
                 )

        assert {:ok, payload} =
                 Map.merge(init_request, %{elmx_manifest: manifest, elmx_revision: revision})
                 |> Ide.Debugger.RuntimeExecutor.execute()

        followups =
          payload
          |> Map.get(:followup_messages, [])
          |> List.wrap()

        refute Enum.any?(followups, fn row ->
                 get_in(row, ["command", "api"]) == "webSocket"
               end),
               "elm-wss init should not emit companion bridge webSocket commands: #{inspect(followups)}"

        runtime_model = get_in(payload.model_patch, ["runtime_model"]) || %{}
        assert runtime_model["status"]["ctor"] == "Closed"
        assert runtime_model["statusDetail"] == "connecting"
      after
        _ = Projects.delete_project(project)
      end
    else
      assert true
    end
  end
end
