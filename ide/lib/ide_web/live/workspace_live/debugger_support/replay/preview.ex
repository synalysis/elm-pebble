defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Replay.Preview do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types

  @type events :: Types.events()
  @type replay_preview_row :: Types.replay_preview_row()
  @type replay_preview_opts :: Types.replay_preview_opts()
  @type replay_target_filter :: Types.replay_target_filter()
  @type replay_preview_target :: Types.replay_preview_target()
  @type maybe_non_neg_integer :: Types.maybe_non_neg_integer()
  @type wire_input :: Types.wire_input()

  @spec rows(events(), replay_preview_opts()) :: [replay_preview_row()]
  def rows(events, opts) when is_list(events) and is_map(opts) do
    count = parse_count(Map.get(opts, :count) || Map.get(opts, "count"))
    target = parse_target(Map.get(opts, :target) || Map.get(opts, "target"))
    cursor_seq = Map.get(opts, :cursor_seq) || Map.get(opts, "cursor_seq")

    events
    |> maybe_filter_events_at_or_before_seq(cursor_seq)
    |> Enum.filter(fn event ->
      event.type == "debugger.update_in" and is_map(event.payload)
    end)
    |> Enum.map(fn event ->
      payload = event.payload
      payload_target = Map.get(payload, :target) || Map.get(payload, "target")
      payload_message = Map.get(payload, :message) || Map.get(payload, "message")
      normalized_target = normalize_target(payload_target)

      %{
        seq: event.seq,
        target: target_label(normalized_target),
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

  @spec parse_count(wire_input()) :: pos_integer()
  defp parse_count(value) when is_integer(value) and value >= 1, do: min(value, 50)

  defp parse_count(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed >= 1 -> min(parsed, 50)
      _ -> 1
    end
  end

  defp parse_count(_value), do: 1

  @spec parse_target(wire_input()) :: replay_target_filter()
  defp parse_target(value) when value in ["watch", "companion", "protocol", "phone"], do: value

  defp parse_target(_value), do: nil

  @spec maybe_filter_events_at_or_before_seq(events(), maybe_non_neg_integer()) :: events()
  defp maybe_filter_events_at_or_before_seq(events, nil) when is_list(events), do: events

  defp maybe_filter_events_at_or_before_seq(events, cursor_seq)
       when is_list(events) and is_integer(cursor_seq) and cursor_seq >= 0 do
    Enum.filter(events, &(&1.seq <= cursor_seq))
  end

  @spec normalize_target(String.t() | atom() | nil) :: replay_preview_target()
  defp normalize_target("watch"), do: "watch"
  defp normalize_target("protocol"), do: "protocol"
  defp normalize_target("companion"), do: "phone"
  defp normalize_target("phone"), do: "phone"
  defp normalize_target(_), do: "watch"

  @spec target_label(replay_preview_target()) :: String.t()
  defp target_label("watch"), do: "watch"
  defp target_label("protocol"), do: "protocol"
  defp target_label("companion"), do: "phone"
  defp target_label("phone"), do: "phone"
  defp target_label(_), do: "watch"
end
