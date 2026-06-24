defmodule Elmc.Backend.Pebble.FeatureFlags.CommandFlags.Services.Speaker do
  @moduledoc false

  alias Elmc.Backend.Pebble.FeatureFlags.TargetSet
  alias Elmc.Backend.Pebble.Types

  @speaker_targets [
    "Pebble.Speaker.isMuted",
    "Pebble.Speaker.playTone",
    "Pebble.Speaker.playNotes",
    "Pebble.Speaker.playTracks",
    "Pebble.Speaker.stop",
    "Pebble.Speaker.setVolume",
    "Pebble.Speaker.status",
    "Pebble.Speaker.streamOpen",
    "Pebble.Speaker.streamWrite",
    "Pebble.Speaker.streamClose",
    "Elm.Kernel.PebbleWatch.speakerIsMuted",
    "Elm.Kernel.PebbleWatch.speakerPlayTone",
    "Elm.Kernel.PebbleWatch.speakerPlayNotes",
    "Elm.Kernel.PebbleWatch.speakerPlayTracks",
    "Elm.Kernel.PebbleWatch.speakerStop",
    "Elm.Kernel.PebbleWatch.speakerSetVolume",
    "Elm.Kernel.PebbleWatch.speakerGetStatus",
    "Elm.Kernel.PebbleWatch.speakerStreamOpen",
    "Elm.Kernel.PebbleWatch.speakerStreamWrite",
    "Elm.Kernel.PebbleWatch.speakerStreamClose"
  ]

  @spec compute(Types.call_target_set()) :: Types.command_speaker_flags()
  def compute(targets) do
    enabled? = Enum.any?(@speaker_targets, &TargetSet.member?(targets, &1))

    %{
      cmd_speaker_is_muted:
        enabled? and
          (TargetSet.member?(targets, "Pebble.Speaker.isMuted") or
             TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.speakerIsMuted")),
      cmd_speaker_play_tone:
        enabled? and
          (TargetSet.member?(targets, "Pebble.Speaker.playTone") or
             TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.speakerPlayTone")),
      cmd_speaker_play_notes:
        enabled? and
          (TargetSet.member?(targets, "Pebble.Speaker.playNotes") or
             TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.speakerPlayNotes")),
      cmd_speaker_play_tracks:
        enabled? and
          (TargetSet.member?(targets, "Pebble.Speaker.playTracks") or
             TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.speakerPlayTracks")),
      cmd_speaker_stop:
        enabled? and
          (TargetSet.member?(targets, "Pebble.Speaker.stop") or
             TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.speakerStop")),
      cmd_speaker_set_volume:
        enabled? and
          (TargetSet.member?(targets, "Pebble.Speaker.setVolume") or
             TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.speakerSetVolume")),
      cmd_speaker_get_status:
        enabled? and
          (TargetSet.member?(targets, "Pebble.Speaker.status") or
             TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.speakerGetStatus")),
      cmd_speaker_stream_open:
        enabled? and
          (TargetSet.member?(targets, "Pebble.Speaker.streamOpen") or
             TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.speakerStreamOpen")),
      cmd_speaker_stream_write:
        enabled? and
          (TargetSet.member?(targets, "Pebble.Speaker.streamWrite") or
             TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.speakerStreamWrite")),
      cmd_speaker_stream_close:
        enabled? and
          (TargetSet.member?(targets, "Pebble.Speaker.streamClose") or
             TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.speakerStreamClose"))
    }
  end
end
