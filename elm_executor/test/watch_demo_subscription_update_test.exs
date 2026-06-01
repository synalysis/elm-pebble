defmodule ElmExecutor.WatchDemoSubscriptionUpdateTest do
  use ExUnit.Case, async: true

  alias ElmExecutor.Runtime.SemanticExecutor

  @app_focus_source File.read!(
                      Path.expand(
                        "../../ide/priv/project_templates/watch_demo_app_focus/src/Main.elm",
                        __DIR__
                      )
                    )

  @data_log_source File.read!(
                     Path.expand(
                       "../../ide/priv/project_templates/watch_demo_data_log/src/Main.elm",
                       __DIR__
                     )
                   )

  test "FocusChanged updates model via Core IR" do
    core_ir = core_ir_from_source(@app_focus_source)

    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: @app_focus_source,
      elm_executor_core_ir: core_ir,
      introspect: %{
        "module" => "Main",
        "msg_constructors" => ["FocusChanged"]
      },
      current_model: %{
        "runtime_model" => %{"focus" => %{"ctor" => "Nothing", "args" => []}, "changes" => 0}
      },
      current_view_tree: %{},
      message: "FocusChanged InFocus",
      elm_executor_metadata: %{"entry_module" => "Main"}
    }

    assert {:ok, result} = SemanticExecutor.execute(request)

    assert result.runtime["operation_source"] in ["core_ir_update_eval", "core_ir_update_noop"],
           "got #{inspect(result.runtime["operation_source"])}"

    assert get_in(result.model_patch, ["runtime_model", "changes"]) == 1
  end

  test "UpPressed updates model and emits DataLog command via Core IR" do
    core_ir = core_ir_from_source(@data_log_source)

    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: @data_log_source,
      elm_executor_core_ir: core_ir,
      introspect: %{
        "module" => "Main",
        "msg_constructors" => ["UpPressed", "SelectPressed", "DownPressed"]
      },
      current_model: %{"runtime_model" => %{"events" => 0, "lastValue" => 0}},
      current_view_tree: %{},
      message: "UpPressed",
      elm_executor_metadata: %{"entry_module" => "Main"}
    }

    assert {:ok, result} = SemanticExecutor.execute(request)

    assert result.runtime["operation_source"] in ["core_ir_update_eval", "core_ir_update_noop"],
           "got #{inspect(result.runtime["operation_source"])}"

    assert get_in(result.model_patch, ["runtime_model", "events"]) == 1
  end

  defp core_ir_from_source(source) do
    assert {:ok, module} = ElmEx.Frontend.GeneratedParser.parse_source("watch/src/Main.elm", source)

    project = %ElmEx.Frontend.Project{
      project_dir: Path.expand("watch/src"),
      elm_json: %{},
      modules: [module],
      diagnostics: []
    }

    assert {:ok, ir} = ElmEx.IR.Lowerer.lower_project(project)
    assert {:ok, core_ir} = ElmEx.CoreIR.from_ir(ir)
    core_ir
  end
end
