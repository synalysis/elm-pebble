defmodule Ide.Debugger.RuntimeExecutorRequestTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.{RuntimeExecutor, Surface}
  alias Ide.Debugger.RuntimeExecutor.Request

  test "build returns struct and to_map feeds executor" do
    surface =
      Surface.from_map(%{
        model: %{"last_path" => "src/Main.elm", "last_source" => "module Main exposing (..)\n"},
        shell: %{"elm_introspect" => %{"module" => "Main"}}
      })

    request = Request.build(surface: surface, message: "Tick", source_root: "watch")
    assert %Request{source_root: "watch", message: "Tick"} = request

    wire = Request.to_map(request)
    assert wire.source_root == "watch"
    assert wire.introspect["module"] == "Main"
    assert {:ok, result} = RuntimeExecutor.execute(request)
    assert is_map(result.model_patch)
  end

  test "validate! accepts wire maps with string keys" do
    wire = %{
      "source_root" => "watch",
      "rel_path" => nil,
      "source" => "",
      "introspect" => %{"module" => "Main"},
      "current_model" => %{},
      "current_view_tree" => %{}
    }

    assert %Request{source_root: "watch"} = Request.validate!(wire)
  end
end
