defmodule Ide.Debugger.CompileIngestTypesTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger

  test "ingest_elmc_check and ingest_elmc_manifest append typed event payloads" do
    slug = "compile_ingest_types_#{System.unique_integer([:positive])}"
    on_exit(fn -> Debugger.forget_project(slug) end)

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.ingest_elmc_check(slug, %{
               status: :ok,
               checked_path: "/tmp/check",
               error_count: 1,
               warning_count: 3
             })

    assert {:ok, _} =
             Debugger.ingest_elmc_manifest(slug, %{
               status: :error,
               manifest_path: "/tmp/manifest",
               detail: "schema mismatch"
             })

    assert {:ok, st} = Debugger.snapshot(slug, event_limit: 20)
    types = Enum.map(st.events, & &1.type)

    assert "debugger.elmc_check" in types
    assert "debugger.elmc_manifest" in types

    check_event = Enum.find(st.events, &(&1.type == "debugger.elmc_check"))
    manifest_event = Enum.find(st.events, &(&1.type == "debugger.elmc_manifest"))

    assert check_event.payload.status == "ok"
    assert check_event.payload.checked_path == "/tmp/check"
    assert check_event.payload.error_count == 1

    assert manifest_event.payload.status == "error"
    assert manifest_event.payload.manifest_path == "/tmp/manifest"
    assert manifest_event.payload.detail == "schema mismatch"
  end
end
