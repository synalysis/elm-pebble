defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Replay.Compare do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types

  @type replay_preview_row :: Types.replay_preview_row()
  @type replay_preview_row_wire :: Types.replay_preview_row_wire()
  @type replay_metadata :: Types.replay_metadata()
  @type replay_compare :: Types.replay_compare()

  @spec compare([replay_preview_row()], replay_metadata() | nil) :: replay_compare()
  def compare(preview_rows, nil) when is_list(preview_rows) do
    %{
      status: :none,
      reason: nil,
      preview_count: length(preview_rows),
      applied_count: 0,
      mismatch_preview: nil,
      mismatch_applied: nil
    }
  end

  def compare(preview_rows, last_replay) when is_list(preview_rows) and is_map(last_replay) do
    applied_rows = normalize_rows(Map.get(last_replay, :replay_preview) || [])
    preview_rows = Enum.map(preview_rows, &normalize_row/1)
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

  @spec normalize_rows([replay_preview_row_wire()]) :: [replay_preview_row()]
  defp normalize_rows(rows) when is_list(rows), do: Enum.map(rows, &normalize_row/1)
  defp normalize_rows(_), do: []

  @spec first_row_mismatch([replay_preview_row()], [replay_preview_row()]) ::
          {replay_preview_row() | nil, replay_preview_row() | nil}
  defp first_row_mismatch(preview_rows, applied_rows) do
    max_len = max(length(preview_rows), length(applied_rows))

    0..max(max_len - 1, 0)
    |> Enum.find_value({List.first(preview_rows), List.first(applied_rows)}, fn index ->
      preview = Enum.at(preview_rows, index)
      applied = Enum.at(applied_rows, index)
      if preview != applied, do: {preview, applied}
    end)
  end

  @spec normalize_row(replay_preview_row_wire()) :: replay_preview_row()
  defp normalize_row(row) when is_map(row) do
    %{
      seq: row[:seq] || row["seq"] || 0,
      target: row[:target] || row["target"] || "watch",
      message: row[:message] || row["message"] || "Tick"
    }
  end

  defp normalize_row(_), do: %{seq: 0, target: "watch", message: "Tick"}
end
