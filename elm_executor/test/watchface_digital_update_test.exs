defmodule ElmExecutor.WatchfaceDigitalUpdateTest do
  use ExUnit.Case, async: true

  alias ElmExecutor.Runtime.SemanticExecutor

  @template_root Path.expand(
                   "../../ide/priv/project_templates/watchface_digital",
                   __DIR__
                 )

  test "MinuteChanged steps via Core IR with getCurrentTimeString cmd" do
    source = File.read!(Path.join([@template_root, "src", "Main.elm"]))

    core_ir =
      core_ir_from_sources([
        {"watch/src/Main.elm", source}
      ])

    runtime_model = %{
      "timeString" => "08:53",
      "screenW" => 144,
      "screenH" => 168,
      "displayShape" => %{"ctor" => "Rectangular", "args" => []}
    }

    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: source,
      elm_executor_core_ir: core_ir,
      introspect: %{
        "module" => "Main",
        "msg_constructors" => ["MinuteChanged", "CurrentTimeString"]
      },
      current_model: %{"runtime_model" => runtime_model},
      current_view_tree: %{},
      message: "MinuteChanged 53",
      elm_executor_metadata: %{"entry_module" => "Main"}
    }

    assert {:ok, result} = SemanticExecutor.execute(request)

    assert result.runtime["operation_source"] == "core_ir_update_noop"

    assert Enum.any?(result.followup_messages || [], fn msg ->
             msg["source"] == "device_command" and msg["message"] == "CurrentTimeString"
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
