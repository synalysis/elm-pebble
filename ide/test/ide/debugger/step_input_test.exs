defmodule Ide.Debugger.StepInputTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.{StepInput, Surface}

  test "from_surface builds typed step input from surface" do
    surface =
      Surface.from_map(%{
        model: %{"runtime_model" => %{"count" => 1}},
        shell: %{"elm_introspect" => %{"module" => "Main"}}
      })

    input = StepInput.from_surface(:watch, surface, "Tick", trigger: "test")

    assert input.target == :watch
    assert input.message == "Tick"
    assert input.trigger == "test"
    assert is_map(input.execution_model)
    assert Map.get(input.execution_model, "elm_introspect") == %{"module" => "Main"}
  end

  test "to_executor_request uses phone source_root for companion target" do
    surface = Surface.from_map(%{model: %{}, shell: %{"elm_introspect" => %{"module" => "Main"}}})
    input = StepInput.from_surface(:companion, surface, "Tick")

    request = StepInput.to_executor_request(input)

    assert request.source_root == "phone"
    assert request.message == "Tick"
    assert is_map(request.introspect)
  end
end
