defmodule IdeWeb.WorkspaceLive.DebuggerSupport do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types

  @type socket :: Types.socket()
  @type maybe_non_neg_integer :: Types.maybe_non_neg_integer()
  @type timeline_kind :: Types.timeline_kind()
  @type event_type_counts :: Types.event_type_counts()
  @type event_summary :: Types.event_summary()
  @type highlight_fragment :: Types.highlight_fragment()
  @type protocol_row :: Types.protocol_row()
  @type update_message_row :: Types.update_message_row()
  @type debugger_row :: Types.debugger_row()
  @type render_event_row :: Types.render_event_row()
  @type lifecycle_row :: Types.lifecycle_row()
  @type replay_preview_row :: Types.replay_preview_row()
  @type replay_compare :: Types.replay_compare()
  @type wire_input :: Types.wire_input()
  @type rendered_node :: Types.rendered_node()
  @type view_tree :: Types.view_tree()
  @type events :: Types.events()
  @type runtime_value :: Types.runtime_value()
  @type debugger_state_map :: Types.debugger_state_map()

  defdelegate assign_defaults(socket), to: IdeWeb.WorkspaceLive.DebuggerSupport.Live
  defdelegate backend_drift_detail(compare, max_reason_len \\ 72), to: IdeWeb.WorkspaceLive.DebuggerSupport.Diagnostics
  defdelegate copy_json(term), to: IdeWeb.WorkspaceLive.DebuggerSupport.Export
  defdelegate debugger_agent_state_markdown(arg1), to: IdeWeb.WorkspaceLive.DebuggerSupport.Export
  defdelegate debugger_message_label(message), to: IdeWeb.WorkspaceLive.DebuggerSupport.Timeline
  defdelegate debugger_rows(source, limit \\ 80), to: IdeWeb.WorkspaceLive.DebuggerSupport.Timeline
  defdelegate debugger_rows_for_mode(arg1, arg2), to: IdeWeb.WorkspaceLive.DebuggerSupport.Timeline
  defdelegate debugger_rows_for_target(rows, target), to: IdeWeb.WorkspaceLive.DebuggerSupport.Timeline
  defdelegate debugger_runtime_status_row?(row), to: IdeWeb.WorkspaceLive.DebuggerSupport.Timeline
  defdelegate debugger_timeline_text(rows), to: IdeWeb.WorkspaceLive.DebuggerSupport.Timeline
  defdelegate diagnostics_preview_at_cursor(events, cursor_seq), to: IdeWeb.WorkspaceLive.DebuggerSupport.Diagnostics
  defdelegate diagnostics_preview_source_label(other), to: IdeWeb.WorkspaceLive.DebuggerSupport.Diagnostics
  defdelegate elm_introspect_at_cursor(events, cursor_seq), to: IdeWeb.WorkspaceLive.DebuggerSupport.Diagnostics
  defdelegate event_diagnostic_preview(arg1), to: IdeWeb.WorkspaceLive.DebuggerSupport.Diagnostics
  defdelegate event_json(events), to: IdeWeb.WorkspaceLive.DebuggerSupport.Timeline
  defdelegate event_summaries(events), to: IdeWeb.WorkspaceLive.DebuggerSupport.Timeline
  defdelegate event_type_counts(events), to: IdeWeb.WorkspaceLive.DebuggerSupport.Timeline
  defdelegate filter_debugger_rows_for_display(arg1, arg2), to: IdeWeb.WorkspaceLive.DebuggerSupport.Timeline
  defdelegate filtered_event_summaries(events, kind, limit), to: IdeWeb.WorkspaceLive.DebuggerSupport.Timeline
  defdelegate filtered_event_summaries(events, kind, limit, query), to: IdeWeb.WorkspaceLive.DebuggerSupport.Timeline
  defdelegate format_elm_introspect_brief(arg1), to: IdeWeb.WorkspaceLive.DebuggerSupport.Export
  defdelegate highlight_fragments(value, query), to: IdeWeb.WorkspaceLive.DebuggerSupport.Timeline
  defdelegate jump_latest(socket), to: IdeWeb.WorkspaceLive.DebuggerSupport.Live
  defdelegate key_target_drift_detail(compare, max_len \\ 72), to: IdeWeb.WorkspaceLive.DebuggerSupport.Diagnostics
  defdelegate lifecycle_events_at_cursor(events, cursor_seq, limit \\ 12), to: IdeWeb.WorkspaceLive.DebuggerSupport.Timeline
  defdelegate max_seq(events), to: IdeWeb.WorkspaceLive.DebuggerSupport.Timeline
  defdelegate maybe_reload(socket, rel_path, content, reason, source_root \\ nil), to: IdeWeb.WorkspaceLive.DebuggerSupport.Live
  defdelegate merge_drift_detail(backend_detail, key_target_detail), to: IdeWeb.WorkspaceLive.DebuggerSupport.Diagnostics
  defdelegate min_seq(events), to: IdeWeb.WorkspaceLive.DebuggerSupport.Timeline
  defdelegate model_diagnostic_preview(arg1), to: IdeWeb.WorkspaceLive.DebuggerSupport.Diagnostics
  defdelegate payload_diff_json(base_event, compare_event), to: IdeWeb.WorkspaceLive.DebuggerSupport.Timeline
  defdelegate protocol_exchange_at_cursor(events, cursor_seq, limit \\ 40), to: IdeWeb.WorkspaceLive.DebuggerSupport.Timeline
  defdelegate refresh(socket), to: IdeWeb.WorkspaceLive.DebuggerSupport.Live
  defdelegate refresh_following_debugger_latest(socket), to: IdeWeb.WorkspaceLive.DebuggerSupport.Live
  defdelegate render_events_at_cursor(events, cursor_seq, limit \\ 24), to: IdeWeb.WorkspaceLive.DebuggerSupport.Timeline
  defdelegate rendered_node_bounds(tree, path, screen_w, screen_h, project \\ nil), to: IdeWeb.WorkspaceLive.DebuggerSupport.Rendered
  defdelegate rendered_node_summary(node, model, arg_name \\ nil), to: IdeWeb.WorkspaceLive.DebuggerSupport.Rendered
  defdelegate rendered_tree(arg1), to: IdeWeb.WorkspaceLive.DebuggerSupport.Rendered
  defdelegate rendered_view_preview(runtime), to: IdeWeb.WorkspaceLive.DebuggerSupport.Rendered
  defdelegate replay_compare(preview_rows, last_replay), to: IdeWeb.WorkspaceLive.DebuggerSupport.Replay
  defdelegate replay_live_drift(mode, preview_seq, events), to: IdeWeb.WorkspaceLive.DebuggerSupport.Replay
  defdelegate replay_live_drift_severity(drift), to: IdeWeb.WorkspaceLive.DebuggerSupport.Replay
  defdelegate replay_live_warning?(mode, preview_seq, events), to: IdeWeb.WorkspaceLive.DebuggerSupport.Replay
  defdelegate replay_metadata_at_cursor(events, cursor_seq), to: IdeWeb.WorkspaceLive.DebuggerSupport.Replay
  defdelegate replay_preview_rows(events, opts), to: IdeWeb.WorkspaceLive.DebuggerSupport.Replay
  defdelegate runtime_fingerprint_compare_at_cursor(events, cursor_seq, compare_cursor_seq), to: IdeWeb.WorkspaceLive.DebuggerSupport.Diagnostics
  defdelegate runtime_fingerprints_at_cursor(events, cursor_seq), to: IdeWeb.WorkspaceLive.DebuggerSupport.Diagnostics
  defdelegate runtime_json(runtime), to: IdeWeb.WorkspaceLive.DebuggerSupport.Rendered
  defdelegate selected_debugger_row(source, cursor_seq), to: IdeWeb.WorkspaceLive.DebuggerSupport.Timeline
  defdelegate seq_bounds(events), to: IdeWeb.WorkspaceLive.DebuggerSupport.Timeline
  defdelegate set_debugger_cursor_seq(socket, value), to: IdeWeb.WorkspaceLive.DebuggerSupport.Live
  defdelegate set_debugger_timeline_mode(socket, value), to: IdeWeb.WorkspaceLive.DebuggerSupport.Live
  defdelegate snapshot_runtime_at_cursor(events, cursor_seq), to: IdeWeb.WorkspaceLive.DebuggerSupport.Live
  defdelegate step_back(socket), to: IdeWeb.WorkspaceLive.DebuggerSupport.Live
  defdelegate step_forward(socket), to: IdeWeb.WorkspaceLive.DebuggerSupport.Live
  defdelegate trigger_buttons(debugger_state), to: IdeWeb.WorkspaceLive.DebuggerSupport.Live
  defdelegate update_messages_at_cursor(events, cursor_seq, limit \\ 40), to: IdeWeb.WorkspaceLive.DebuggerSupport.Timeline
  defdelegate view_tree_outline(runtime), to: IdeWeb.WorkspaceLive.DebuggerSupport.Diagnostics
end
