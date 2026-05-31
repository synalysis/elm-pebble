defmodule Ide.Debugger.RuntimeModelQualityTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.RuntimeModelQuality

  test "findings lists parser artifact field names" do
    model = %{
      "runtime_model" => %{
        "layout" => %{"call" => "Render.layoutFor", "args" => []},
        "screenW" => 144
      }
    }

    assert RuntimeModelQuality.unresolved_field_names(model) == ["layout"]
    assert ["runtime_model_has_parser_artifacts: layout"] = RuntimeModelQuality.findings(model)
  end

  test "public_runtime_model drops parser artifacts for export" do
    model = %{
      "runtime_model" => %{
        "layout" => %{"call" => "Render.layoutFor", "args" => []},
        "screenW" => 144
      }
    }

    assert RuntimeModelQuality.public_runtime_model(model) == %{"screenW" => 144}
  end
end
