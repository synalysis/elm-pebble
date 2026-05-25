defmodule ElmExecutor.WeatherViewPreviewTest do
  use ExUnit.Case, async: true

  alias ElmExecutor.Runtime.SemanticExecutor

  test "derive_view_output_preview renders fog vector from weatherIconOps helper" do
    runtime_model = %{
      "suppressWeatherTransitions" => false,
      "displayedCondition" => %{"ctor" => "Just", "args" => [%{"ctor" => "Fog", "args" => []}]},
      "temperature" => %{"ctor" => "Just", "args" => [%{"ctor" => "Celsius", "args" => [18]}]},
      "screenW" => 144,
      "screenH" => 168
    }

    view_tree = %{
      "type" => "weatherIconOps",
      "label" => "weatherIconOps",
      "children" => [
        %{"type" => "var", "value" => "model"},
        %{"type" => "var", "value" => "iconOrigin"}
      ]
    }

    introspect = %{
      "module" => "Main",
      "function_types" => %{
        "Main|weatherIconOps|2" => "Model -> Ui.Point -> List Ui.RenderOp"
      }
    }

    context = %{
      vector_resource_indices: %{"WeatherFog" => 3},
      elm_introspect: introspect
    }

    output = SemanticExecutor.derive_view_output_preview(view_tree, runtime_model, context)

    assert output != [], "expected some view output, got: #{inspect(output)}"

    assert Enum.any?(output, fn row ->
             row["kind"] == "vector_at" and row["vector_id"] == 3
           end)
  end
end
