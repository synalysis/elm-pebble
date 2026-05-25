defmodule Ide.Debugger.ImportTraceTypesTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger

  test "import_trace round-trips minimal export body" do
    slug = "import_trace_#{System.unique_integer([:positive])}"
    on_exit(fn -> Debugger.forget_project(slug) end)

    assert {:ok, _} = Debugger.start_session(slug)
    assert {:ok, _} = Debugger.step(slug, %{"target" => "watch", "message" => "Tick"})
    assert {:ok, %{json: json}} = Debugger.export_trace(slug)
    body = Jason.decode!(json)

    assert body["export_version"] == 1
    assert body["project_slug"] == slug
    assert is_list(body["events"])

    assert {:ok, imported} = Debugger.import_trace(slug, body, strict_slug: true)

    assert imported.running == true
    assert imported.project_slug == slug
    assert length(imported.events) == length(body["events"])
  end
end
