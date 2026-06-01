defmodule Ide.Debugger.RuntimePreviewTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.CoreIRFixtures
  alias Ide.Debugger.RuntimePreview

  test "render_view_from_surface does not reuse parser expression view tree when Core IR is attached" do
    parser_tree = %{
      "type" => "toUiNode",
      "label" => "Ui.toUiNode [ Ui.clear Color.black ]",
      "children" => [%{"type" => "expr", "label" => "Ui.clear Color.black"}]
    }

    introspect = %{
      "module" => "Main",
      "view_tree" => parser_tree,
      "view_return_kind" => "custom_record",
      "view_return_type" => "UiNode"
    }

    surface = %{
      model: %{
        "runtime_model" => %{
          "n" => 1,
          "enabled" => false,
          "screenW" => 144,
          "screenH" => 168
        },
        "launch_context" => %{"screen" => %{"width" => 144, "height" => 168}}
      },
      shell:
        Map.merge(
          %{"debugger_contract" => introspect},
          CoreIRFixtures.step_input_attrs()
        ),
      view_tree: parser_tree
    }

    preview = RuntimePreview.render_view_from_surface(surface, :watch)
    view_type = get_in(preview, [:view_tree, "type"])

    refute view_type == "toUiNode",
           "expected Core IR-derived preview tree, got parser expression tree"

    assert view_type in ["windowStack", "window", "previewUnavailable"]
  end

  test "render_view_from_surface reports previewUnavailable when Core IR is missing" do
    introspect = %{"module" => "Main", "view_tree" => %{"type" => "windowStack", "children" => []}}

    surface = %{
      model: %{"runtime_model" => %{}},
      shell: %{"debugger_contract" => introspect},
      view_tree: %{}
    }

    preview = RuntimePreview.render_view_from_surface(surface, :watch)

    assert get_in(preview, [:view_tree, "type"]) == "previewUnavailable"

    assert (get_in(preview, [:model, "runtime_view_output"]) || []) == []
  end
end
