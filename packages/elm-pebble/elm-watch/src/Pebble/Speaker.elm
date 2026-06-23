module Pebble.Speaker exposing
    ( FinishReason(..)
    , Limits
    , Note
    , PcmFormat(..)
    , Status(..)
    , Track
    , Waveform(..)
    , isMuted
    , limits
    , maxNotes
    , maxSampleBytesTotal
    , maxTracks
    , onFinished
    , playNotes
    , playTone
    , playTracks
    , setVolume
    , status
    , stop
    , streamClose
    , streamOpen
    , streamWrite
    )

{-| Speaker playback for Pebble watches with `PBL_SPEAKER`.

Use `limits` to validate note and track counts before calling `playNotes` or `playTracks`.
Subscribe with `onFinished` before starting playback when you need completion callbacks.

    import Pebble.Speaker as Speaker

    type Msg
        = PlayMelody
        | SpeakerFinished Speaker.FinishReason

    melody : List Speaker.Note
    melody =
        [ { midiNote = 60, waveform = Speaker.Sine, durationMs = 120, velocity = 100 }
        , { midiNote = 64, waveform = Speaker.Sine, durationMs = 120, velocity = 100 }
        , { midiNote = 67, waveform = Speaker.Sine, durationMs = 200, velocity = 100 }
        ]

    update msg model =
        case msg of
            PlayMelody ->
                ( model, Speaker.playNotes melody 80 )

            SpeakerFinished Speaker.FinishedDone ->
                ( { model | playing = False }, Cmd.none )

            _ ->
                ( model, Cmd.none )

    subscriptions _ =
        Speaker.onFinished SpeakerFinished

For PCM-backed tracks, set `sample = Just …` on each `Track` using values from
`Pebble.Speaker.Resources`. See the **watch-demo-speaker** project template.

@docs Waveform, Note, Track, PcmFormat, Status, FinishReason, Limits, limits, maxNotes, maxTracks, maxSampleBytesTotal, playTone, playNotes, playTracks, stop, setVolume, status, isMuted, streamOpen, streamWrite, streamClose, onFinished

-}

import Elm.Kernel.PebbleWatch
import Pebble.Speaker.Resources exposing (Sample)


{-| Synthesizer waveform for tones and notes.
-}
type Waveform
    = Sine
    | Square
    | Triangle
    | Sawtooth


{-| A single note in a monophonic sequence.
-}
type alias Note =
    { midiNote : Int
    , waveform : Waveform
    , durationMs : Int
    , velocity : Int
    }


{-| A monophonic voice for `playTracks`.

Set `sample` to `Just` a value from `Pebble.Speaker.Resources` for PCM-backed playback.
-}
type alias Track =
    { notes : List Note
    , sample : Maybe Sample
    }


{-| Mono PCM stream format for `streamOpen`.
-}
type PcmFormat
    = Pcm8kHz8bit
    | Pcm16kHz8bit
    | Pcm8kHz16bit
    | Pcm16kHz16bit


{-| Current speaker activity reported by `status`.
-}
type Status
    = Idle
    | Playing
    | Draining


{-| Why speaker playback ended.
-}
type FinishReason
    = FinishedDone
    | FinishedStopped
    | FinishedPreempted
    | FinishedError
    | FinishedUnknown


{-| Speaker playback limits exposed by the Pebble SDK.
-}
type alias Limits =
    { maxNotes : Int
    , maxTracks : Int
    , maxSampleBytesTotal : Int
    }


{-| SDK `SPEAKER_MAX_NOTES`.
-}
maxNotes : Int
maxNotes =
    256


{-| SDK `SPEAKER_MAX_TRACKS`.
-}
maxTracks : Int
maxTracks =
    4


{-| SDK `SPEAKER_MAX_SAMPLE_BYTES_TOTAL` (16 KiB).
-}
maxSampleBytesTotal : Int
maxSampleBytesTotal =
    16 * 1024


{-| All speaker validation limits in one record.
-}
limits : Limits
limits =
    { maxNotes = maxNotes
    , maxTracks = maxTracks
    , maxSampleBytesTotal = maxSampleBytesTotal
    }


{-| Play a single tone.

`frequencyHz` is the tone frequency. `durationMs` is capped at 10 seconds on device.
`volume` is `0`–`100`.
-}
playTone : Int -> Int -> Int -> Waveform -> Cmd msg
playTone frequencyHz durationMs volume waveform =
    Elm.Kernel.PebbleWatch.speakerPlayTone frequencyHz durationMs volume (waveformToInt waveform)


{-| Play a monophonic note sequence at the given global volume (`0`–`100`).
-}
playNotes : List Note -> Int -> Cmd msg
playNotes notes volume =
    Elm.Kernel.PebbleWatch.speakerPlayNotes notes volume


{-| Play up to four monophonic tracks mixed together.

Each track is a sequential note list. Use `sample = Just …` from `Pebble.Speaker.Resources`
for PCM-backed tracks; leave `sample = Nothing` for synthesized waveforms.
-}
playTracks : List Track -> Int -> Cmd msg
playTracks tracks volume =
    Elm.Kernel.PebbleWatch.speakerPlayTracks tracks volume


{-| Stop any active speaker playback immediately.
-}
stop : Cmd msg
stop =
    Elm.Kernel.PebbleWatch.speakerStop


{-| Set the global speaker volume (`0`–`100`), including during playback.
-}
setVolume : Int -> Cmd msg
setVolume volume =
    Elm.Kernel.PebbleWatch.speakerSetVolume volume


{-| Poll the current speaker status.
-}
status : (Status -> msg) -> Cmd msg
status =
    Elm.Kernel.PebbleWatch.speakerGetStatus


{-| Check whether the watch speaker is muted system-wide.
-}
isMuted : (Bool -> msg) -> Cmd msg
isMuted =
    Elm.Kernel.PebbleWatch.speakerIsMuted


{-| Open a raw PCM stream at the given format and starting volume.
-}
streamOpen : PcmFormat -> Int -> Cmd msg
streamOpen format volume =
    Elm.Kernel.PebbleWatch.speakerStreamOpen (pcmFormatToInt format) volume


{-| Write signed PCM bytes (`0`–`255` wire encoding) to the open stream.
-}
streamWrite : List Int -> Cmd msg
streamWrite bytes =
    Elm.Kernel.PebbleWatch.speakerStreamWrite bytes


{-| Close the open PCM stream and drain buffered audio.
-}
streamClose : Cmd msg
streamClose =
    Elm.Kernel.PebbleWatch.speakerStreamClose


{-| Receive speaker playback completion events.

Register this subscription before starting playback that needs a completion callback.
-}
onFinished : (FinishReason -> msg) -> Sub msg
onFinished =
    Elm.Kernel.PebbleWatch.onSpeakerFinished


waveformToInt : Waveform -> Int
waveformToInt waveform =
    case waveform of
        Sine ->
            0

        Square ->
            1

        Triangle ->
            2

        Sawtooth ->
            3


pcmFormatToInt : PcmFormat -> Int
pcmFormatToInt format =
    case format of
        Pcm8kHz8bit ->
            0

        Pcm16kHz8bit ->
            1

        Pcm8kHz16bit ->
            2

        Pcm16kHz16bit ->
            3
