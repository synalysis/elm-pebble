defmodule Ide.Debugger.ReplayRecent do
  @moduledoc false

  alias Ide.Debugger.Attrs
  alias Ide.Debugger.ReplaySession
  alias Ide.Debugger.SurfaceTargets
  alias Ide.Debugger.Types

  @type normalize_target_fn :: (Types.wire_input() -> Types.surface_target())
  @type replay_label_fn :: (Types.surface_target() | nil -> String.t())

  @type apply_step_fn ::
          (Types.runtime_state(),
           Types.surface_target(),
           String.t(),
           Types.subscription_payload()
           | nil,
           String.t(),
           String.t() ->
             Types.runtime_state())

  @type append_event_fn ::
          (Types.runtime_state(), String.t(), Types.debugger_timeline_payload() ->
             Types.runtime_state())

  @type host :: %{
          required(:apply_step_once) => apply_step_fn(),
          required(:append_event) => append_event_fn(),
          required(:normalize_target) => normalize_target_fn(),
          required(:replay_label) => replay_label_fn()
        }

  @spec apply(Types.runtime_state(), Types.replay_attrs(), host()) :: Types.runtime_state()
  def apply(state, attrs, host) when is_map(state) and is_map(attrs) and is_map(host) do
    if Map.get(state, :running, false) do
      count = Attrs.parse_step_count(Map.get(attrs, :count) || Map.get(attrs, "count"))

      target =
        SurfaceTargets.normalize_optional(Map.get(attrs, :target) || Map.get(attrs, "target"))

      cursor_seq =
        Attrs.parse_optional_cursor_seq(
          Map.get(attrs, :cursor_seq) || Map.get(attrs, "cursor_seq")
        )

      replay_mode =
        ReplaySession.parse_mode(Map.get(attrs, :replay_mode) || Map.get(attrs, "replay_mode"))

      replay_drift_seq =
        Attrs.parse_optional_cursor_seq(
          Map.get(attrs, :replay_drift_seq) || Map.get(attrs, "replay_drift_seq")
        )

      replay_rows? = Map.has_key?(attrs, :replay_rows) or Map.has_key?(attrs, "replay_rows")

      replay_rows =
        ReplaySession.normalize_rows_input(
          Map.get(attrs, :replay_rows) || Map.get(attrs, "replay_rows"),
          host.normalize_target
        )

      {replay_messages, replay_source} =
        if replay_rows? do
          {replay_rows, "frozen_preview"}
        else
          {ReplaySession.recent_update_messages(
             state,
             target,
             count,
             cursor_seq,
             host.normalize_target
           ), "recent_query"}
        end

      replayed =
        Enum.reduce(replay_messages, state, fn %{target: replay_target, message: message}, acc ->
          host.apply_step_once.(acc, replay_target, message, nil, "replay", "replay")
        end)

      requested_count = if replay_rows?, do: length(replay_rows), else: count
      replayed_count = length(replay_messages)

      replay_payload =
        Types.ReplayEventPayload.build(
          host.replay_label.(target),
          requested_count,
          replayed_count,
          replay_source,
          cursor_seq,
          Types.ReplayEventPayload.telemetry(
            replay_mode,
            replay_source,
            replay_drift_seq,
            host.replay_label.(target),
            requested_count,
            replayed_count
          ),
          replay_messages
        )

      host.append_event.(replayed, "debugger.replay", replay_payload)
    else
      state
    end
  end
end
