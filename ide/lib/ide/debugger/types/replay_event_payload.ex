defmodule Ide.Debugger.Types.ReplayEventPayload do
  @moduledoc "Payload for `debugger.replay` batch replay events."

  alias Ide.Debugger.Types

  @type replay_telemetry :: %{
          optional(:mode) => String.t(),
          optional(:source) => String.t(),
          optional(:drift_seq) => non_neg_integer(),
          optional(:drift_band) => String.t(),
          optional(:target_scope) => String.t() | nil,
          optional(:requested_count) => non_neg_integer(),
          optional(:replayed_count) => non_neg_integer(),
          optional(:used_frozen_preview) => boolean(),
          optional(:used_live_query) => boolean(),
          optional(atom()) => term(),
          optional(String.t()) => term()
        }

  @type t :: %{
          optional(:target) => String.t() | nil,
          optional(:requested_count) => non_neg_integer(),
          optional(:replayed_count) => non_neg_integer(),
          optional(:replay_source) => String.t(),
          optional(:cursor_seq) => non_neg_integer() | nil,
          optional(:replay_telemetry) => replay_telemetry(),
          optional(:replay_target_counts) => map(),
          optional(:replay_message_counts) => map(),
          optional(:replay_preview) => [map()],
          optional(atom()) => term(),
          optional(String.t()) => term()
        }

  @spec telemetry(
          String.t(),
          String.t(),
          integer() | nil,
          String.t() | nil,
          non_neg_integer(),
          non_neg_integer()
        ) :: replay_telemetry()
  def telemetry(mode, source, drift_seq, target_scope, requested_count, replayed_count)
      when is_binary(mode) and is_binary(source) and is_integer(requested_count) and
             is_integer(replayed_count) and replayed_count >= 0 do
    %{
      mode: mode,
      source: source,
      drift_seq: drift_seq || 0,
      drift_band: drift_band(drift_seq),
      target_scope: target_scope,
      requested_count: requested_count,
      replayed_count: replayed_count,
      used_frozen_preview: source == "frozen_preview",
      used_live_query: source == "recent_query"
    }
  end

  @spec summary([Types.replay_row()]) :: %{
          replay_target_counts: map(),
          replay_message_counts: map(),
          replay_preview: [map()]
        }
  def summary(messages) when is_list(messages) do
    target_counts =
      Enum.reduce(messages, %{}, fn row, acc ->
        target = Map.get(row, :target) || Map.get(row, "target")
        key = replay_target_label(target)
        Map.update(acc, key, 1, &(&1 + 1))
      end)

    message_counts =
      Enum.reduce(messages, %{}, fn row, acc ->
        message = Map.get(row, :message) || Map.get(row, "message")
        Map.update(acc, message, 1, &(&1 + 1))
      end)

    preview =
      messages
      |> Enum.take(8)
      |> Enum.map(fn row ->
        %{
          seq: Map.get(row, :seq) || Map.get(row, "seq"),
          target: replay_target_label(Map.get(row, :target) || Map.get(row, "target")),
          message: Map.get(row, :message) || Map.get(row, "message")
        }
      end)

    %{
      replay_target_counts: target_counts,
      replay_message_counts: message_counts,
      replay_preview: preview
    }
  end

  @spec build(
          String.t() | nil,
          non_neg_integer(),
          non_neg_integer(),
          String.t(),
          non_neg_integer() | nil,
          replay_telemetry(),
          [Types.replay_row()]
        ) :: t()
  def build(target, requested_count, replayed_count, replay_source, cursor_seq, telemetry, messages)
      when is_integer(requested_count) and is_integer(replayed_count) and is_binary(replay_source) and
             is_map(telemetry) and is_list(messages) do
    %{
      target: target,
      requested_count: requested_count,
      replayed_count: replayed_count,
      replay_source: replay_source,
      cursor_seq: cursor_seq,
      replay_telemetry: telemetry
    }
    |> Map.merge(summary(messages))
  end

  @spec drift_band(integer() | nil) :: String.t()
  def drift_band(nil), do: "none"
  def drift_band(drift) when is_integer(drift) and drift <= 0, do: "none"
  def drift_band(drift) when is_integer(drift) and drift <= 3, do: "mild"
  def drift_band(drift) when is_integer(drift) and drift <= 10, do: "medium"
  def drift_band(_drift), do: "high"

  @spec replay_target_label(Types.surface_target() | String.t() | atom() | nil) :: String.t()
  defp replay_target_label(nil), do: "all"
  defp replay_target_label(target) when target in [:watch, :companion, :phone], do: Atom.to_string(target)
  defp replay_target_label(target) when is_binary(target), do: target
  defp replay_target_label(target) when is_atom(target), do: Atom.to_string(target)
  defp replay_target_label(_target), do: "all"
end
