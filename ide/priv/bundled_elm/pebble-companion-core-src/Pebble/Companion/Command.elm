module Pebble.Companion.Command exposing (command, withPayload)

{-| Build command envelopes for the JavaScript companion bridge.

Most higher-level companion modules use this module internally, but it is handy
when you need to talk to a custom bridge API.

    import Json.Encode as Encode
    import Pebble.Companion.Command as Command

    vibrateCommand =
        Command.command "cmd-1" "watch" "vibrate"
            |> Command.withPayload (Encode.object [])

# Command envelopes
@docs command, withPayload

-}

import Json.Encode as Encode
import Pebble.Companion.Contract exposing (CommandEnvelope)


{-| Build a command envelope with an empty payload.
-}
command : String -> String -> String -> CommandEnvelope
command id api op =
    { id = id
    , api = api
    , op = op
    , payload = Encode.object []
    }


{-| Replace payload on an existing command envelope.
-}
withPayload : Encode.Value -> CommandEnvelope -> CommandEnvelope
withPayload payload envelope =
    { envelope | payload = payload }
