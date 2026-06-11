defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Diagnostics do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Diagnostics.{Cursor, Fingerprint, Preview, ViewTree}

  defdelegate view_tree_outline(runtime), to: ViewTree, as: :outline

  defdelegate model_diagnostic_preview(runtime), to: Preview
  defdelegate event_diagnostic_preview(event), to: Preview
  defdelegate diagnostics_preview_at_cursor(events, cursor_seq), to: Cursor
  defdelegate diagnostics_preview_source_label(source), to: Preview

  defdelegate debugger_contract_at_cursor(events, cursor_seq), to: Cursor
  defdelegate elm_introspect_at_cursor(events, cursor_seq), to: Cursor
  defdelegate runtime_fingerprints_at_cursor(events, cursor_seq), to: Cursor, as: :fingerprints_at_cursor

  defdelegate runtime_fingerprint_compare_at_cursor(events, cursor_seq, compare_cursor_seq),
    to: Fingerprint

  defdelegate backend_drift_detail(compare, max_reason_len \\ 72), to: Fingerprint
  defdelegate key_target_drift_detail(compare, max_len \\ 72), to: Fingerprint
  defdelegate merge_drift_detail(backend_detail, key_target_detail), to: Fingerprint
end
