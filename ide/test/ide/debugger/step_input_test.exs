defmodule Ide.Debugger.StepInputTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.StepInput
  alias Ide.Debugger.Surface

  describe "from_surface/4" do
    test "captures app and execution models from surface" do
      surface =
        Surface.from_map(%{
          model: %{"runtime_model" => %{"count" => 1}, "status" => "idle"},
          shell: %{"elm_introspect" => %{"module" => "Main"}}
        })

      step = StepInput.from_surface(:watch, surface, "Tick", message_value: %{"ctor" => "Tick", "args" => []})

      assert step.app_model["status"] == "idle"
      assert step.execution_model["elm_introspect"]["module"] == "Main"
      assert step.message == "Tick"
      assert step.message_value == %{"ctor" => "Tick", "args" => []}
    end

    test "with_app_model updates surface snapshot" do
      surface = Surface.from_map(%{model: %{"count" => 0}, shell: %{}})
      step = StepInput.from_surface(:watch, surface, "Tick")

      updated = StepInput.with_app_model(step, %{"count" => 1, "runtime_model" => %{"latitudeE6" => 0}})

      assert updated.app_model["count"] == 1
      assert Surface.app_model(updated.surface)["count"] == 1
    end
  end
end
