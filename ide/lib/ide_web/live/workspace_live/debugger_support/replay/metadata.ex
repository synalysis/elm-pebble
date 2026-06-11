defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Replay.Metadata do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Util

  @type events :: Types.events()
  @type replay_metadata :: Types.replay_metadata()
  @type maybe_non_neg_integer :: Types.maybe_non_neg_integer()

  @spec at_cursor(events(), maybe_non_neg_integer()) :: replay_metadata() | nil
  def at_cursor(events, cursor_seq) when is_list(events) do
    upper = Util.timeline_upper_seq(events, cursor_seq)

    events
    |> Enum.find(fn event ->
      event.type == "debugger.replay" and is_map(event.payload) and event.seq <= upper
    end)
    |> case do
      nil ->
        nil

      event ->
        payload = event.payload

        %{
          seq: event.seq,
          target: Util.map_string(payload, :target),
          replay_source: Util.map_string(payload, :replay_source),
          requested_count: Util.map_integer(payload, :requested_count),
          replayed_count: Util.map_integer(payload, :replayed_count),
          cursor_seq: Util.map_integer(payload, :cursor_seq),
          replay_telemetry: Util.map_map(payload, :replay_telemetry),
          replay_target_counts: Util.map_map(payload, :replay_target_counts),
          replay_message_counts: Util.map_map(payload, :replay_message_counts),
          replay_preview: Util.map_list(payload, :replay_preview)
        }
    end
  end
end
