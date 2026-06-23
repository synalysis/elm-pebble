defmodule Ide.Debugger.SpeakerPlayback do
  @moduledoc false

  @spec duration_ms(map()) :: non_neg_integer()
  def duration_ms(%{"variant" => "play_tone"} = command) do
    command
    |> Map.get("duration_ms", Map.get(command, :duration_ms, 200))
    |> normalize_duration_ms()
  end

  def duration_ms(%{"variant" => "play_notes"} = command) do
    command
    |> Map.get("note_values", Map.get(command, :note_values, []))
    |> note_sequence_duration_ms()
  end

  def duration_ms(%{"variant" => "play_tracks"} = command) do
    command
    |> Map.get("track_values", Map.get(command, :track_values, []))
    |> tracks_duration_ms(Map.get(command, "volume", Map.get(command, :volume, 50)))
  end

  def duration_ms(%{"variant" => "stop"}), do: 0
  def duration_ms(_command), do: 0

  @spec note_sequence_duration_ms([number()]) :: non_neg_integer()
  def note_sequence_duration_ms(note_values) when is_list(note_values) do
    note_values
    |> Enum.chunk_every(4, 4, :discard)
    |> Enum.reduce(0, fn
      [_midi, _waveform, duration_ms, _velocity], acc ->
        acc + normalize_duration_ms(duration_ms)

      _quad, acc ->
        acc
    end)
  end

  def note_sequence_duration_ms(_note_values), do: 0

  @spec tracks_duration_ms([number()], number()) :: non_neg_integer()
  def tracks_duration_ms(track_values, global_volume) when is_list(track_values) do
    tracks_duration_ms(track_values, global_volume, 0, 0)
  end

  def tracks_duration_ms(_track_values, _global_volume), do: 0

  defp tracks_duration_ms(track_values, global_volume, cursor, total)
       when is_list(track_values) and cursor < length(track_values) do
    note_count = Enum.at(track_values, cursor, 0)
    sample_index_cursor = cursor + 1

    if note_count <= 0 or sample_index_cursor >= length(track_values) do
      total
    else
      slice_start = sample_index_cursor + 1
      slice = Enum.slice(track_values, slice_start, note_count * 4)
      next_cursor = slice_start + note_count * 4

      tracks_duration_ms(
        track_values,
        global_volume,
        next_cursor,
        total + note_sequence_duration_ms(slice)
      )
    end
  end

  defp tracks_duration_ms(_track_values, _global_volume, _cursor, total), do: total

  defp normalize_duration_ms(value) when is_integer(value) and value > 0, do: value
  defp normalize_duration_ms(value) when is_float(value), do: value |> Float.round() |> trunc() |> normalize_duration_ms()
  defp normalize_duration_ms(_value), do: 1
end
