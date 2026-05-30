defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Replay do
  @moduledoc false
  @dialyzer :no_match

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Util
  @spec replay_preview_rows([map()], map()) :: [Types.replay_preview_row()]
  def replay_preview_rows(events, opts) when is_list(events) and is_map(opts) do
    count = parse_replay_count(Map.get(opts, :count) || Map.get(opts, "count"))
    target = parse_replay_target(Map.get(opts, :target) || Map.get(opts, "target"))
    cursor_seq = Map.get(opts, :cursor_seq) || Map.get(opts, "cursor_seq")

    events
    |> maybe_filter_preview_events_at_or_before_seq(cursor_seq)
    |> Enum.filter(fn event ->
      event.type == "debugger.update_in" and is_map(event.payload)
    end)
    |> Enum.map(fn event ->
      payload = event.payload
      payload_target = Map.get(payload, :target) || Map.get(payload, "target")
      payload_message = Map.get(payload, :message) || Map.get(payload, "message")
      normalized_target = normalize_preview_target(payload_target)

      %{
        seq: event.seq,
        target: preview_target_label(normalized_target),
        message:
          if(is_binary(payload_message) and payload_message != "",
            do: payload_message,
            else: "Tick"
          ),
        normalized_target: normalized_target
      }
    end)
    |> Enum.filter(fn row ->
      is_nil(target) or row.normalized_target == target
    end)
    |> Enum.take(count)
    |> Enum.reverse()
    |> Enum.map(fn row ->
      %{seq: row.seq, target: row.target, message: row.message}
    end)
  end

  @spec replay_metadata_at_cursor([map()], Types.maybe_non_neg_integer()) :: map() | nil
  def replay_metadata_at_cursor(events, cursor_seq) when is_list(events) do
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

  @spec replay_compare([Types.replay_preview_row()], map() | nil) :: Types.replay_compare()
  def replay_compare(preview_rows, nil) when is_list(preview_rows) do
    %{
      status: :none,
      reason: nil,
      preview_count: length(preview_rows),
      applied_count: 0,
      mismatch_preview: nil,
      mismatch_applied: nil
    }
  end

  def replay_compare(preview_rows, last_replay)
      when is_list(preview_rows) and is_map(last_replay) do
    applied_rows = normalize_replay_rows(Map.get(last_replay, :replay_preview) || [])
    preview_rows = Enum.map(preview_rows, &normalize_replay_row/1)
    applied_count = Map.get(last_replay, :replayed_count) || length(applied_rows)

    cond do
      length(preview_rows) != applied_count ->
        %{
          status: :mismatch,
          reason: "count",
          preview_count: length(preview_rows),
          applied_count: applied_count,
          mismatch_preview: List.first(preview_rows),
          mismatch_applied: List.first(applied_rows)
        }

      preview_rows != applied_rows ->
        {mismatch_preview, mismatch_applied} = first_row_mismatch(preview_rows, applied_rows)

        %{
          status: :mismatch,
          reason: "rows",
          preview_count: length(preview_rows),
          applied_count: applied_count,
          mismatch_preview: mismatch_preview,
          mismatch_applied: mismatch_applied
        }

      true ->
        %{
          status: :match,
          reason: nil,
          preview_count: length(preview_rows),
          applied_count: applied_count,
          mismatch_preview: nil,
          mismatch_applied: nil
        }
    end
  end

  @spec replay_live_warning?(String.t(), Types.maybe_non_neg_integer(), [map()]) :: boolean()
  def replay_live_warning?(mode, preview_seq, events) when is_binary(mode) and is_list(events) do
    latest_seq =
      case events do
        [] ->
          nil

        list ->
          list
          |> Enum.map(& &1.seq)
          |> Enum.max()
      end

    mode == "live" and is_integer(preview_seq) and is_integer(latest_seq) and
      latest_seq > preview_seq
  end

  @spec replay_live_drift(String.t(), Types.maybe_non_neg_integer(), [map()]) :: non_neg_integer() | nil
  def replay_live_drift(mode, preview_seq, events) when is_binary(mode) and is_list(events) do
    latest_seq =
      case events do
        [] -> nil
        list -> list |> Enum.map(& &1.seq) |> Enum.max()
      end

    if mode == "live" and is_integer(preview_seq) and is_integer(latest_seq) and
         latest_seq > preview_seq do
      latest_seq - preview_seq
    end
  end

  @spec replay_live_drift_severity(non_neg_integer() | nil) :: :none | :mild | :medium | :high
  def replay_live_drift_severity(nil), do: :none
  def replay_live_drift_severity(drift) when is_integer(drift) and drift <= 3, do: :mild
  def replay_live_drift_severity(drift) when is_integer(drift) and drift <= 10, do: :medium
  def replay_live_drift_severity(drift) when is_integer(drift), do: :high
  @spec parse_replay_count(Types.wire_input()) :: pos_integer()
  defp parse_replay_count(value) when is_integer(value) and value >= 1, do: min(value, 50)

  defp parse_replay_count(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed >= 1 -> min(parsed, 50)
      _ -> 1
    end
  end

  defp parse_replay_count(_value), do: 1

  @spec parse_replay_target(Types.wire_input()) :: String.t() | nil
  defp parse_replay_target(value) when value in ["watch", "companion", "protocol", "phone"],
    do: value

  defp parse_replay_target(_value), do: nil

  @spec normalize_replay_rows(list()) :: [Types.replay_preview_row()]
  defp normalize_replay_rows(rows) when is_list(rows), do: Enum.map(rows, &normalize_replay_row/1)
  defp normalize_replay_rows(_), do: []

  @spec first_row_mismatch([Types.replay_preview_row()], [Types.replay_preview_row()]) ::
          {Types.replay_preview_row() | nil, Types.replay_preview_row() | nil}
  defp first_row_mismatch(preview_rows, applied_rows) do
    max_len = max(length(preview_rows), length(applied_rows))

    0..max(max_len - 1, 0)
    |> Enum.find_value({List.first(preview_rows), List.first(applied_rows)}, fn index ->
      preview = Enum.at(preview_rows, index)
      applied = Enum.at(applied_rows, index)
      if preview != applied, do: {preview, applied}
    end)
  end

  @spec normalize_replay_row(map()) :: Types.replay_preview_row()
  defp normalize_replay_row(row) when is_map(row) do
    %{
      seq: row[:seq] || row["seq"] || 0,
      target: row[:target] || row["target"] || "watch",
      message: row[:message] || row["message"] || "Tick"
    }
  end

  defp normalize_replay_row(_), do: %{seq: 0, target: "watch", message: "Tick"}

  @spec maybe_filter_preview_events_at_or_before_seq(Types.events(), Types.maybe_non_neg_integer()) :: Types.events()
  defp maybe_filter_preview_events_at_or_before_seq(events, nil) when is_list(events), do: events

  defp maybe_filter_preview_events_at_or_before_seq(events, cursor_seq)
       when is_list(events) and is_integer(cursor_seq) and cursor_seq >= 0 do
    Enum.filter(events, &(&1.seq <= cursor_seq))
  end

  @spec normalize_preview_target(String.t() | atom()) :: String.t()
  defp normalize_preview_target("watch"), do: "watch"
  defp normalize_preview_target("protocol"), do: "protocol"
  defp normalize_preview_target("companion"), do: "phone"
  defp normalize_preview_target("phone"), do: "phone"
  defp normalize_preview_target(_), do: "watch"

  @spec preview_target_label(String.t()) :: String.t()
  defp preview_target_label("watch"), do: "watch"
  defp preview_target_label("protocol"), do: "protocol"
  defp preview_target_label("companion"), do: "phone"
  defp preview_target_label("phone"), do: "phone"
  defp preview_target_label(_), do: "watch"
end
