defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Replay do
  @moduledoc false
  @dialyzer :no_match

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Replay.{Compare, LiveDrift, Metadata, Preview}
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types

  @type events :: Types.events()
  @type replay_preview_row :: Types.replay_preview_row()
  @type replay_preview_opts :: Types.replay_preview_opts()
  @type replay_metadata :: Types.replay_metadata()
  @type replay_compare :: Types.replay_compare()
  @type maybe_non_neg_integer :: Types.maybe_non_neg_integer()
  @type replay_drift_severity :: Types.replay_drift_severity()

  defdelegate replay_preview_rows(events, opts), to: Preview, as: :rows
  defdelegate replay_metadata_at_cursor(events, cursor_seq), to: Metadata, as: :at_cursor
  defdelegate replay_compare(preview_rows, last_replay), to: Compare, as: :compare
  defdelegate replay_live_warning?(mode, preview_seq, events), to: LiveDrift, as: :warning?
  defdelegate replay_live_drift(mode, preview_seq, events), to: LiveDrift, as: :drift
  defdelegate replay_live_drift_severity(drift), to: LiveDrift, as: :severity
end
