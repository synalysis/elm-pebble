defmodule Ide.Debugger.ReplaySession do
  @moduledoc false

  alias Ide.Debugger.Types

  @type normalize_target_fn :: (Types.wire_input() -> Types.surface_target())

  @spec parse_mode(Types.wire_input()) :: String.t()
  def parse_mode("live"), do: "live"
  def parse_mode("frozen"), do: "frozen"
  def parse_mode(_), do: "unknown"

  @spec normalize_rows_input(
          [Types.replay_row() | Types.ReplayRow.wire_map()],
          normalize_target_fn()
        ) ::
          [Types.replay_row()]
  def normalize_rows_input(rows, normalize_target) when is_function(normalize_target, 1) do
    rows
    |> List.wrap()
    |> Enum.filter(&is_map/1)
    |> Enum.map(fn row ->
      seq = Map.get(row, :seq) || Map.get(row, "seq") || 0
      target = Map.get(row, :target) || Map.get(row, "target")
      message = Map.get(row, :message) || Map.get(row, "message")

      %{
        seq: if(is_integer(seq), do: seq, else: 0),
        target: normalize_target.(target),
        message: if(is_binary(message) and message != "", do: message, else: "Tick")
      }
    end)
  end

  @spec recent_update_messages(
          Types.runtime_state(),
          Types.surface_target() | nil,
          pos_integer(),
          non_neg_integer() | nil,
          normalize_target_fn()
        ) :: [Types.replay_row()]
  def recent_update_messages(state, target, count, cursor_seq, normalize_target)
      when is_map(state) and is_integer(count) and is_function(normalize_target, 1) do
    state
    |> Map.get(:events, [])
    |> Ide.Debugger.EventLogFilters.at_or_before_seq(cursor_seq)
    |> Enum.filter(fn event ->
      event.type == "debugger.update_in" and is_map(event.payload)
    end)
    |> Enum.map(fn event ->
      payload = event.payload
      payload_target = Map.get(payload, :target) || Map.get(payload, "target")
      payload_message = Map.get(payload, :message) || Map.get(payload, "message")

      %{
        seq: event.seq,
        target: normalize_target.(payload_target),
        message:
          if(is_binary(payload_message) and payload_message != "",
            do: payload_message,
            else: "Tick"
          )
      }
    end)
    |> Enum.filter(fn %{target: replay_target} ->
      is_nil(target) or replay_target == target
    end)
    |> Enum.take(count)
    |> Enum.reverse()
  end
end
