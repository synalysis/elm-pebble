defmodule Ide.Debugger.ExportTraceTypesTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger

  test "export_trace returns typed json sha256 and byte_size" do
    slug = "export_trace_result_#{System.unique_integer([:positive])}"
    on_exit(fn -> Debugger.forget_project(slug) end)

    assert {:ok, _} = Debugger.start_session(slug)
    assert {:ok, _} = Debugger.step(slug, %{"target" => "watch", "message" => "Tick"})

    assert {:ok, result} = Debugger.export_trace(slug, event_limit: 10)

    assert is_binary(result.json)
    assert is_binary(result.sha256)
    assert result.byte_size > 0
    assert String.length(result.sha256) == 64

    body = Jason.decode!(result.json)
    assert body["export_version"] == 1
    assert body["project_slug"] == slug
  end
end
