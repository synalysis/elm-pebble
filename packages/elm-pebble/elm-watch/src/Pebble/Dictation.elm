module Pebble.Dictation exposing (Error(..), Status(..), start, stop, onStatus, onResult)

{-| Voice dictation via the Pebble microphone and phone speech recognition.

Start a session with `start`, subscribe to `onStatus` and `onResult`, and call
`stop` to cancel early if needed.

    import Pebble.Dictation as Dictation

    type Msg
        = StartDictation
        | DictationStatus Dictation.Status
        | DictationResult (Result Dictation.Error String)

    update msg model =
        case msg of
            StartDictation ->
                ( model, Dictation.start )

            DictationResult (Ok text) ->
                ( { model | transcript = text }, Cmd.none )

            _ ->
                ( model, Cmd.none )

    subscriptions _ =
        Sub.batch
            [ Dictation.onStatus DictationStatus
            , Dictation.onResult DictationResult
            ]

For a runnable example, use the **watch-demo-dictation** project template in the IDE.

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
