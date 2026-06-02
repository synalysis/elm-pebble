defmodule Ide.Debugger.RuntimeExecutorRequestTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.Surface
  alias Ide.Debugger.RuntimeExecutor.Request

  test "build returns struct and to_map feeds executor" do
    surface =
      Surface.from_map(%{
        model: %{"last_path" => "src/Main.elm", "last_source" => "module Main exposing (..)\n"},
        shell:
          Map.merge(
            %{"debugger_contract" => %{"module" => "Main"}},
            %{
              "elmx_manifest" => %{"contract" => "elmx.runtime_executor.v1"},
              "elmx_revision" => "request-test"
            }
          )
      })

    request = Request.build(surface: surface, message: "Tick", source_root: "watch")
    assert %Request{source_root: "watch", message: "Tick"} = request

    wire = Request.to_map(request)
    assert wire.source_root == "watch"
    assert wire.introspect["module"] == "Main"
    assert wire.elmx_manifest["contract"] == "elmx.runtime_executor.v1"
    assert wire.elmx_revision == "request-test"
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

  test "validate_execution_ready! requires versioned elmx artifacts" do
    wire = %{
      "source_root" => "watch",
      "rel_path" => nil,
      "source" => "",
      "introspect" => %{"module" => "Main"},
      "current_model" => %{},
      "current_view_tree" => %{}
    }

    assert_raise ArgumentError, ~r/elmx_manifest and elmx_revision/, fn ->
      Request.validate_execution_ready!(wire)
    end

    ready =
      Map.merge(wire, %{
        "elmx_manifest" => %{"contract" => "elmx.runtime_executor.v1"},
        "elmx_revision" => "request-test"
      })

    assert %Request{} = Request.validate_execution_ready!(ready)
  end
end
