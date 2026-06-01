defmodule Ide.Debugger.CoreIrPhoneConnectivityTest do
  use Ide.DataCase, async: false

  alias ElmEx.CoreIR
  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.Lowerer
  alias Ide.Debugger.CompiledElixirCorpusHelpers, as: Corpus
  alias Ide.Debugger.RuntimeExecutor
  alias Ide.Mcp.DebuggerTemplateCorpus

  @enabled? Corpus.corpus_enabled?()

  test "core_ir GotConnectivity Online step sets online when corpus enabled" do
    if @enabled? and "companion-demo-phone-status" in DebuggerTemplateCorpus.template_keys() do
      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template("companion-demo-phone-status", cleanup: false)

      try do
        phone_workspace =
          project |> Ide.Projects.project_workspace_path() |> Path.join("phone")

        {:ok, core_project} = Bridge.load_project(phone_workspace)
        {:ok, ir} = Lowerer.lower_project(core_project)
        {:ok, core_ir} = CoreIR.from_ir(ir, strict?: false)

        message_value = Corpus.companion_got_connectivity_value("Online")

        request = %{
          source_root: "phone",
          rel_path: "src/CompanionApp.elm",
          source: "",
          introspect: %{},
          current_model: %{"runtime_model" => %{"online" => false}},
          current_view_tree: %{},
          message: "GotConnectivity",
          message_value: message_value,
          elm_executor_core_ir: core_ir,
          elm_executor_metadata: %{"entry_module" => "CompanionApp"}
        }

        Application.put_env(:ide, RuntimeExecutor, execution_backend: :core_ir)

        assert {:ok, payload} = RuntimeExecutor.execute(request)
        assert payload.model_patch["runtime_model"]["online"] == true
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end
end
