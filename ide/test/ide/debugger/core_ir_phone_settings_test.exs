defmodule Ide.Debugger.CoreIrPhoneSettingsTest do
  use Ide.DataCase, async: false

  alias ElmEx.CoreIR
  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.Lowerer
  alias Ide.Debugger.CompiledElixirCorpusHelpers, as: Corpus
  alias Ide.Debugger.RuntimeExecutor
  alias Ide.Mcp.DebuggerTemplateCorpus

  @enabled? Corpus.corpus_enabled?()

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "core_ir LifecycleChanged Ready step sets ready when corpus enabled" do
    if @enabled? and "companion-demo-settings" in DebuggerTemplateCorpus.template_keys() do
      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template("companion-demo-settings", cleanup: false)

      try do
        phone_workspace =
          project |> Ide.Projects.project_workspace_path() |> Path.join("phone")

        {:ok, core_project} = Bridge.load_project(phone_workspace)
        {:ok, ir} = Lowerer.lower_project(core_project)
        {:ok, core_ir} = CoreIR.from_ir(ir, strict?: false)

        message_value = Corpus.companion_lifecycle_changed_value("Ready")

        request = %{
          source_root: "phone",
          rel_path: "src/CompanionApp.elm",
          source: "",
          introspect: %{},
          current_model: %{
            "runtime_model" => %{
              "ready" => false,
              "visible" => true,
              "configOutcome" => %{"ctor" => "Nothing", "args" => []}
            }
          },
          current_view_tree: %{},
          message: "LifecycleChanged",
          message_value: message_value,
          elm_executor_core_ir: core_ir,
          elm_executor_metadata: %{"entry_module" => "CompanionApp"}
        }

        Application.put_env(:ide, RuntimeExecutor, execution_backend: :core_ir)

        assert {:ok, payload} = RuntimeExecutor.execute(request)
        assert payload.model_patch["runtime_model"]["ready"] == true
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "core_ir ConfigurationClosed Just step sets Saved outcome when corpus enabled" do
    if @enabled? and "companion-demo-settings" in DebuggerTemplateCorpus.template_keys() do
      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template("companion-demo-settings", cleanup: false)

      try do
        phone_workspace =
          project |> Ide.Projects.project_workspace_path() |> Path.join("phone")

        {:ok, core_project} = Bridge.load_project(phone_workspace)
        {:ok, ir} = Lowerer.lower_project(core_project)
        {:ok, core_ir} = CoreIR.from_ir(ir, strict?: false)

        message_value = Corpus.companion_configuration_closed_value("saved")

        request = %{
          source_root: "phone",
          rel_path: "src/CompanionApp.elm",
          source: "",
          introspect: %{},
          current_model: %{
            "runtime_model" => %{
              "ready" => false,
              "visible" => true,
              "configOutcome" => %{"ctor" => "Nothing", "args" => []}
            }
          },
          current_view_tree: %{},
          message: "ConfigurationClosed",
          message_value: message_value,
          elm_executor_core_ir: core_ir,
          elm_executor_metadata: %{"entry_module" => "CompanionApp"}
        }

        Application.put_env(:ide, RuntimeExecutor, execution_backend: :core_ir)

        assert {:ok, payload} = RuntimeExecutor.execute(request)

        outcome = payload.model_patch["runtime_model"]["configOutcome"]
        assert outcome["ctor"] == "Just"
        assert hd(outcome["args"])["ctor"] == "Saved"
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end
end
