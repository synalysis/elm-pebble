defmodule ElmExecutor.VectorViewPreviewTest do
  use ExUnit.Case, async: true

  alias ElmExecutor.Runtime.SemanticExecutor

  test "derive_view_output_preview collects drawVectorAt ops from list render helper subtree" do
    runtime_model = %{
      "screenW" => 144,
      "screenH" => 168
    }

    view_tree = %{
      "type" => "iconOps",
      "label" => "iconOps",
      "children" => [
        %{"type" => "var", "value" => "model"},
        %{"type" => "var", "value" => "origin"}
      ]
    }

    introspect = %{
      "module" => "Main",
      "function_types" => %{
        "Main|iconOps|2" => "Model -> Ui.Point -> List Ui.RenderOp"
      },
      "function_view_trees" => %{
        "Main|iconOps|2" => %{
          "type" => "List",
          "children" => [
            %{
              "type" => "drawVectorAt",
              "children" => [
                %{"type" => "expr", "value" => %{"ctor" => "WeatherFog", "args" => []}},
                %{"type" => "expr", "value" => 48},
                %{"type" => "expr", "value" => 102}
              ]
            }
          ]
        }
      }
    }

    context = %{
      vector_resource_indices: %{"WeatherFog" => 3},
      elm_introspect: introspect
    }

    output = SemanticExecutor.derive_view_output_preview(view_tree, runtime_model, context)

    assert Enum.any?(output, fn row ->
             row["kind"] == "vector_at" and row["vector_id"] == 3 and row["x"] == 48 and row["y"] == 102
           end)
  end

  test "drawVectorAt with conditionVector resolves vector id from runtime Just ctor fields" do
    runtime_model = %{
      "displayedCondition" => %{"ctor" => "Just", "args" => [%{"ctor" => "Fog", "args" => []}]},
      "screenW" => 144,
      "screenH" => 168
    }

    view_tree = %{
      "type" => "drawVectorAt",
      "children" => [
        %{
          "type" => "conditionVector",
          "children" => [%{"type" => "var", "value" => "condition"}]
        },
        %{"type" => "var", "value" => "origin"}
      ]
    }

    context = %{
      vector_resource_indices: %{"WeatherFog" => 3},
      view_param_bindings: %{"origin" => %{"ctor" => "Point", "args" => [48, 102]}}
    }

    output = SemanticExecutor.derive_view_output_preview(view_tree, runtime_model, context)

    assert Enum.any?(output, fn row ->
             row["kind"] == "vector_at" and row["vector_id"] == 3 and row["x"] == 48 and row["y"] == 102
           end)
  end

  test "drawVectorAt resolves vector id from runtime model without origin binding" do
    runtime_model = %{
      "displayedCondition" => %{"ctor" => "Just", "args" => [%{"ctor" => "Fog", "args" => []}]},
      "screenW" => 144,
      "screenH" => 168
    }

    view_tree = %{
      "type" => "drawVectorAt",
      "children" => [
        %{
          "type" => "conditionVector",
          "children" => [%{"type" => "var", "value" => "condition"}]
        },
        %{"type" => "var", "value" => "origin"}
      ]
    }

    context = %{vector_resource_indices: %{"WeatherFog" => 3}}

    output = SemanticExecutor.derive_view_output_preview(view_tree, runtime_model, context)

    assert Enum.any?(output, fn row ->
             row["kind"] == "vector_at" and row["vector_id"] == 3
           end)
  end
end
