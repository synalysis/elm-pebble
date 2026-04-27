module Pebble.Companion.AppMessage exposing (decodeIncoming, send, subscribeIncoming)

{-| Send and receive Pebble AppMessage payloads from the phone companion.

    import Json.Encode as Encode
    import Pebble.Companion.AppMessage as AppMessage

    sendTemperature =
        AppMessage.send "weather-1" (Encode.int 72)

# Commands
@docs send, subscribeIncoming

# Events
@docs decodeIncoming

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (BridgeEvent, CommandEnvelope)


{-| Send a typed payload from companion to watch via AppMessage.
-}
send : String -> Encode.Value -> CommandEnvelope
send id payload =
    Command.command id "appMessage" "send"
        |> Command.withPayload payload


{-| Subscribe companion bridge side to incoming watch AppMessage traffic.
-}
subscribeIncoming : String -> CommandEnvelope
subscribeIncoming id =
    Command.command id "appMessage" "subscribe"


{-| Decode an incoming AppMessage event payload.

Expected event name: `appMessage.incoming`.
-}
decodeIncoming : BridgeEvent -> Result String Decode.Value
decodeIncoming event =
    if event.event == "appMessage.incoming" then
        Ok event.payload

    else
        Err ("Unexpected event: " ++ event.event)
