defmodule Ide.Debugger.ElmcDiagnosticPreviewTypesTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger

  test "ingest_elmc_check with diagnostics attaches typed preview on event payload" do
    slug = "elmc_diag_preview_#{System.unique_integer([:positive])}"
    on_exit(fn -> Debugger.forget_project(slug) end)

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.ingest_elmc_check(slug, %{
               status: :error,
               checked_path: "/tmp/check",
               error_count: 1,
               warning_count: 0,
               diagnostics: [
                 %{
                   severity: :error,
                   message: "Type mismatch in update",
                   file: "src/Main.elm",
                   line: 12,
                   column: 4
                 }
               ]
             })

    assert {:ok, st} = Debugger.snapshot(slug, event_limit: 5)
    event = Enum.find(st.events, &(&1.type == "debugger.elmc_check"))
    assert event

    [row | _] = event.payload.diagnostic_preview
    assert row["severity"] == "error"
    assert String.contains?(row["message"], "Type mismatch")
    assert row["file"] == "src/Main.elm"
    assert row["line"] == 12
    assert get_in(st.watch, [:model, "elmc_diagnostic_preview"]) != nil
  end
end
