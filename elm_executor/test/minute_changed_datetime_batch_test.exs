defmodule ElmExecutor.MinuteChangedDateTimeBatchTest do
  use ExUnit.Case, async: true

  alias ElmExecutor.Runtime.SemanticExecutor

  @template_root Path.expand(
                   "../../ide/priv/project_templates/watchface_poke_battle",
                   __DIR__
                 )

  @minute_batch_replacement "MinuteChanged _ ->\n            ( model, Cmd.batch [ refreshSteps model, Time.currentDateTime CurrentDateTime ] )"

  setup context do
    replacement = Map.get(context, :minute_replacement, @minute_batch_replacement)

    source =
      @template_root
      |> Path.join("src/Main.elm")
      |> File.read!()
      |> String.replace(
        "MinuteChanged _ ->\n            ( model, refreshSteps model )",
        replacement
      )

    core_ir =
      core_ir_from_sources([
        {"watch/src/Main.elm", source}
      ])

    {:ok, source: source, core_ir: core_ir}
  end

  test "HourChanged emits CurrentDateTime device followup", %{source: source, core_ir: core_ir} do
    assert {:ok, result} =
             execute(source, core_ir, "HourChanged 12", %{"healthSupported" => true})

    assert device_followup?(result, "CurrentDateTime")
  end

  @tag minute_replacement:
           "MinuteChanged _ ->\n            ( model, Time.currentDateTime CurrentDateTime )"
  test "MinuteChanged with only currentDateTime emits device followup", %{
    source: source,
    core_ir: core_ir
  } do
    assert {:ok, result} = execute(source, core_ir, "MinuteChanged 54", %{"healthSupported" => true})
    assert device_followup?(result, "CurrentDateTime")
  end

  test "MinuteChanged with refreshSteps and currentDateTime in Cmd.batch emits both followups", %{
    source: source,
    core_ir: core_ir
  } do
    assert {:ok, result} = execute(source, core_ir, "MinuteChanged 54", %{"healthSupported" => true})

    assert device_followup?(result, "CurrentDateTime")
    assert Enum.any?(result.followup_messages || [], &(&1["source"] == "device_command"))
  end

  defp execute(source, core_ir, message, runtime_model_extra) do
    SemanticExecutor.execute(%{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: source,
      elm_executor_core_ir: core_ir,
      introspect: %{
        "module" => "Main",
        "msg_constructors" => ["MinuteChanged", "HourChanged", "CurrentDateTime", "StepsToday"]
      },
      current_model: %{
        "runtime_model" =>
          Map.merge(
            %{
              "screenW" => 144,
              "screenH" => 168,
              "displayShape" => %{"ctor" => "Rectangular", "args" => []}
            },
            runtime_model_extra
          )
      },
      current_view_tree: %{},
      message: message,
      elm_executor_metadata: %{"entry_module" => "Main"}
    })
  end

  defp device_followup?(result, message) do
    Enum.any?(result.followup_messages || [], fn row ->
      row["source"] == "device_command" and row["message"] == message
    end)
  end

  defp core_ir_from_sources(sources) when is_list(sources) do
    modules =
      Enum.map(sources, fn {path, source} ->
        assert {:ok, module} = ElmEx.Frontend.GeneratedParser.parse_source(path, source)
        module
      end)

    project = %ElmEx.Frontend.Project{
      project_dir: Path.expand("watch/src"),
      elm_json: %{},
      modules: modules,
      diagnostics: []
    }

    assert {:ok, ir} = ElmEx.IR.Lowerer.lower_project(project)
    assert {:ok, core_ir} = ElmEx.CoreIR.from_ir(ir)
    core_ir
  end
end
