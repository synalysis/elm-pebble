defmodule Elmx.Runtime.Pebble.Dispatch.Speaker do
  @moduledoc false

  alias Elmx.Runtime.Cmd
  alias Elmx.Types

  @spec play_tone_cmd(Types.registry_args()) :: Types.wire_cmd()
  def play_tone_cmd([frequency_hz, duration_ms, volume, waveform | _]) do
    Cmd.effect("speaker",
      variant: "play_tone",
      extra: %{
        "frequency_hz" => coerce_int(frequency_hz),
        "duration_ms" => coerce_int(duration_ms),
        "volume" => coerce_int(volume),
        "waveform" => coerce_int(waveform)
      }
    )
  end

  def play_tone_cmd(_), do: Cmd.effect("speaker", variant: "play_tone")

  @spec play_notes_cmd(Types.registry_args()) :: Types.wire_cmd()
  def play_notes_cmd([notes, volume | _]) do
    Cmd.effect("speaker",
      variant: "play_notes",
      extra: %{
        "volume" => coerce_int(volume),
        "note_values" => note_wire_values(notes)
      }
    )
  end

  def play_notes_cmd(_), do: Cmd.effect("speaker", variant: "play_notes")

  @spec play_tracks_cmd(Types.registry_args()) :: Types.wire_cmd()
  def play_tracks_cmd([tracks, volume | _]) do
    Cmd.effect("speaker",
      variant: "play_tracks",
      extra: %{
        "volume" => coerce_int(volume),
        "track_values" => track_wire_values(tracks)
      }
    )
  end

  def play_tracks_cmd(_), do: Cmd.effect("speaker", variant: "play_tracks")

  @spec stop_cmd(Types.registry_args()) :: Types.wire_cmd()
  def stop_cmd(_), do: Cmd.effect("speaker", variant: "stop")

  @spec set_volume_cmd(Types.registry_args()) :: Types.wire_cmd()
  def set_volume_cmd([volume | _]) do
    Cmd.effect("speaker", variant: "set_volume", extra: %{"volume" => coerce_int(volume)})
  end

  def set_volume_cmd(_), do: Cmd.effect("speaker", variant: "set_volume")

  defp note_wire_values(values) when is_list(values) do
    case values do
      [first | _] when is_integer(first) ->
        Enum.map(values, &coerce_int/1)

      _ ->
        Enum.flat_map(values, &note_record_values/1)
    end
  end

  defp note_wire_values(_), do: []

  defp note_record_values(note) when is_map(note) do
    [
      field_int(note, "midiNote"),
      field_int(note, "waveform"),
      field_int(note, "durationMs"),
      field_int(note, "velocity")
    ]
  end

  defp note_record_values(note) when is_integer(note), do: [note]
  defp note_record_values(_), do: []

  defp track_wire_values(tracks) when is_list(tracks) do
    Enum.flat_map(tracks, fn
      track when is_map(track) ->
        notes = Map.get(track, "notes") || Map.get(track, :notes) || []
        sample_index = sample_index_from_track(track)
        [length(notes), sample_index | note_wire_values(notes)]

      track when is_integer(track) ->
        [track]

      _ ->
        []
    end)
  end

  defp track_wire_values(_), do: []

  defp sample_index_from_track(track) when is_map(track) do
    case Map.get(track, "sample") || Map.get(track, :sample) do
      %{"ctor" => "Nothing"} -> 0
      %{ctor: :Nothing} -> 0
      %{"ctor" => "Just", "args" => [sample]} -> sample_index_value(sample)
      %{ctor: :Just, args: [sample]} -> sample_index_value(sample)
      _ -> 0
    end
  end

  defp sample_index_value(sample) when is_integer(sample), do: sample

  defp sample_index_value(sample) when is_map(sample) do
    case Map.get(sample, "ctor") || Map.get(sample, :ctor) do
      ctor when is_binary(ctor) -> sample_ctor_index(ctor)
      ctor when is_atom(ctor) -> sample_ctor_index(Atom.to_string(ctor))
      _ -> 0
    end
  end

  defp sample_index_value(_), do: 0

  defp sample_ctor_index("NoSample"), do: 0
  defp sample_ctor_index(_ctor), do: 1

  defp field_int(map, field) do
    map
    |> Map.get(field)
    |> case do
      nil -> Map.get(map, String.to_atom(field))
      value -> value
    end
    |> coerce_int()
  end

  defp coerce_int(value) when is_integer(value), do: value
  defp coerce_int(value) when is_float(value), do: trunc(value)
  defp coerce_int(_), do: 0
end
