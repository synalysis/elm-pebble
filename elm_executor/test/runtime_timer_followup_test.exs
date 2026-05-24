defmodule ElmExecutor.Runtime.TimerFollowupTest do
  use ExUnit.Case, async: true

  alias ElmExecutor.Runtime.SemanticExecutor

  @template_root Path.expand(
                   "../../ide/priv/project_templates/watchface_weather_animated",
                   __DIR__
                 )

  test "timer followups resolve Msg constructors instead of imported protocol tags with the same number" do
    watch_source = File.read!(Path.join([@template_root, "src", "Main.elm"]))
    types_source = File.read!(Path.join([@template_root, "protocol", "src", "Companion", "Types.elm"]))

    core_ir =
      core_ir_from_sources([
        {"watch/protocol/src/Companion/Types.elm", types_source},
        {"watch/src/Main.elm", watch_source}
      ])

    runtime_model = %{
      "temperature" => %{"ctor" => "Just", "args" => [%{"ctor" => "Celsius", "args" => [23]}]},
      "condition" => %{"ctor" => "Just", "args" => [%{"ctor" => "Fog", "args" => []}]},
      "displayedCondition" => %{"ctor" => "Just", "args" => [%{"ctor" => "Fog", "args" => []}]},
      "activeTransition" => %{"ctor" => "Nothing", "args" => []},
      "suppressWeatherTransitions" => false,
      "screenW" => 144,
      "screenH" => 168,
      "now" => %{"ctor" => "Nothing", "args" => []}
    }

    request = %{
      source_root: "watch",
      rel_path: "src/Main.elm",
      source: watch_source,
      elm_executor_core_ir: core_ir,
      introspect: %{
        module: "Main",
        msg_constructors: [
          "CurrentDateTime",
          "FromPhone",
          "MinuteChanged",
          "TransitionFinished",
          "EnableWeatherTransitions"
        ],
        update_case_branches: [
          "CurrentDateTime value",
          "FromPhone message",
          "MinuteChanged _",
          "TransitionFinished",
          "EnableWeatherTransitions"
        ]
      },
      current_model: %{"runtime_model" => runtime_model},
      current_view_tree: %{},
      message: "FromPhone (ProvideCondition Snow)",
      message_value: %{
        "ctor" => "FromPhone",
        "args" => [
          %{"ctor" => "ProvideCondition", "args" => [%{"ctor" => "Snow", "args" => []}]}
        ]
      },
      update_branches: []
    }

    assert {:ok, result} = SemanticExecutor.execute(request)

    assert [%{"message" => "TransitionFinished", "source" => "timer_command"}] =
             result.followup_messages
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
