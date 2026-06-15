defmodule Ide.Debugger.StepExecutionViewOutputTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.StepExecution

  test "view_output_captured_for_model? detects pageIndex changes" do
    base = %{
      "runtime_model" => %{"pageIndex" => 2, "screenW" => 200, "screenH" => 228},
      "runtime_view_output" => [%{"kind" => "text", "text" => "Text 3/8"}]
    }

    tagged = StepExecution.tag_runtime_view_output_capture(base)
    assert StepExecution.view_output_captured_for_model?(tagged)

    refute StepExecution.view_output_captured_for_model?(
             put_in(tagged, ["runtime_model", "pageIndex"], 3)
           )
  end

  test "placeholder_view_tree? rejects executor empty stub and previewUnavailable" do
    refute StepExecution.introspect_view_usable?(%{"type" => "empty", "children" => []}, %{})
    refute StepExecution.introspect_view_usable?(%{"type" => "previewUnavailable", "children" => []}, %{})

    assert StepExecution.introspect_view_usable?(
             %{"type" => "windowStack", "children" => [%{"type" => "window", "children" => []}]},
             %{}
           )
  end

  test "introspect_parser_view_tree prefers contract view_tree over executor empty stub" do
    execution_model = %{
      "debugger_contract" => %{
        "view_tree" => %{
          "type" => "windowStack",
          "children" => [%{"type" => "window", "children" => []}]
        }
      }
    }

    assert %{"type" => "windowStack"} =
             StepExecution.introspect_parser_view_tree(
               execution_model,
               %{"type" => "empty", "children" => []}
             )
  end

  test "should_refresh_executor_view_preview? when scene signatures differ" do
    app_model = %{"runtime_model" => %{"pageIndex" => 3}}

    stored = [
      %{"kind" => "clear", "color" => 255},
      %{"kind" => "text", "x" => 0, "y" => 2, "w" => 200, "h" => 18, "text" => "Text 4/8"}
    ]

    fresh = [
      %{"kind" => "clear", "color" => 255},
      %{"kind" => "bitmap_in_rect", "bitmap_id" => 1, "x" => 8, "y" => 30, "w" => 30, "h" => 30}
    ]

    assert StepExecution.should_refresh_executor_view_preview?(app_model, stored, fresh)
  end
end
