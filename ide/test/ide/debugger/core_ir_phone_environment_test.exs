defmodule Ide.Debugger.CoreIrPhoneEnvironmentTest do
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
  test "core_ir GotEnvironment Ok step sets sun and moon fields when corpus enabled" do
    if @enabled? and "companion-demo-weather-env" in DebuggerTemplateCorpus.template_keys() do
      assert {:ok, %{project: project}} =
               DebuggerTemplateCorpus.bootstrap_template("companion-demo-weather-env", cleanup: false)

      try do
        phone_workspace =
          project |> Ide.Projects.project_workspace_path() |> Path.join("phone")

        {:ok, core_project} = Bridge.load_project(phone_workspace)
        {:ok, ir} = Lowerer.lower_project(core_project)
        {:ok, core_ir} = CoreIR.from_ir(ir, strict?: false)

        info = Corpus.companion_environment_info(sunrise_min: 360, sunset_min: 1140, phase_e6: 750_000)
        message_value = Corpus.companion_got_environment_ok_value(info)

        request = %{
          source_root: "phone",
          rel_path: "src/CompanionApp.elm",
          source: "",
          introspect: %{},
          current_model: %{
            "runtime_model" => %{
              "temperatureC" => 0,
              "condition" => %{"ctor" => "UnknownWeather", "args" => []},
              "sunriseMin" => 0,
              "sunsetMin" => 0,
              "moonPhaseE6" => 0
            }
          },
          current_view_tree: %{},
          message: "GotEnvironment",
          message_value: message_value,
          elm_executor_core_ir: core_ir,
          elm_executor_metadata: %{"entry_module" => "CompanionApp"}
        }

        Application.put_env(:ide, RuntimeExecutor, execution_backend: :core_ir)

        assert {:ok, payload} = RuntimeExecutor.execute(request)

        model = payload.model_patch["runtime_model"]
        assert model["sunriseMin"] == 360
        assert model["sunsetMin"] == 1140
        assert model["moonPhaseE6"] == 750_000
      after
        _ = Ide.Projects.delete_project(project)
      end
    else
      assert true
    end
  end
end
