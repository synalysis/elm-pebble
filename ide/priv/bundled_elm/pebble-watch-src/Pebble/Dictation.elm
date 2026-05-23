module Pebble.Dictation exposing (Error(..), Status(..), start, stop, onStatus, onResult)

{-| Voice dictation via the Pebble microphone and phone speech recognition.

@docs Error, Status, start, stop, onStatus, onResult

-}

import Elm.Kernel.PebbleWatch


{-| Dictation session errors.
-}
type Error
    = NoMicrophone
    | PhoneDisconnected
    | Cancelled
    | Failed String


{-| Dictation session lifecycle status.
-}
type Status
    = Starting
    | Recognizing
    | Finished


{-| Start a dictation session.
-}
start : Cmd msg
start =
    Elm.Kernel.PebbleWatch.dictationStart


{-| Stop an in-progress dictation session.
-}
stop : Cmd msg
stop =
    Elm.Kernel.PebbleWatch.dictationStop


{-| Receive dictation status updates.
-}
onStatus : (Status -> msg) -> Sub msg
onStatus =
    Elm.Kernel.PebbleWatch.onDictationStatus


{-| Receive the transcribed text or an error when the session completes.
-}
onResult : (Result Error String -> msg) -> Sub msg
onResult =
    Elm.Kernel.PebbleWatch.onDictationResult
