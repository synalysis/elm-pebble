defmodule Ide.Debugger.CompiledElixirPhoneBridgeFollowupsTest do
  use Ide.DataCase, async: false

  alias Ide.Debugger.CompiledElixirCorpusHelpers, as: Corpus
  alias Ide.Mcp.DebuggerTemplateCorpus
  alias Ide.Projects

  @enabled? Corpus.corpus_enabled?()

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-websocket phone init emits Connected bridge followup when enabled" do
    if @enabled? and "companion-demo-websocket" in DebuggerTemplateCorpus.template_keys() do
      Corpus.ensure_compiled_elixir_backend!()

      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template("companion-demo-websocket", cleanup: false)

      try do
        phone_workspace =
          project |> Projects.project_workspace_path() |> Path.join("phone")

        revision = "corpus-ws-followups-" <> Integer.to_string(:erlang.unique_integer([:positive]))

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

        assert Enum.any?(followups, fn row ->
                 (Map.get(row, "message") || Map.get(row, :message)) == "Connected" or
                   get_in(row, ["command", "api"]) == "webSocket"
               end),
               "expected webSocket/Connected followup, got: #{inspect(followups)}"

        runtime_model = get_in(payload.model_patch, ["runtime_model"]) || %{}

        final_model =
          Corpus.corpus_apply_companion_bridge_init_followups(
            Map.merge(init_request, %{elmx_manifest: manifest, elmx_revision: revision}),
            runtime_model,
            payload,
            apply_companion_bridge_followups: true
          )

        assert final_model["status"]["ctor"] == "Open"
        assert final_model["statusDetail"] == "connected"
      after
        _ = Projects.delete_project(project)
      end
    else
      assert true
    end
  end
end
