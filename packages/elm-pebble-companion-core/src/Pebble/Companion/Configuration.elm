module Pebble.Companion.Configuration exposing (Event(..), open, subscribe, decode)

{-| Open and observe the Pebble companion configuration page.

    Pebble.Companion.Configuration.open "settings" "https://example.com/config"

# Events
@docs Event, decode

# Commands
@docs open, subscribe

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (BridgeEvent, CommandEnvelope)


{-| Configuration lifecycle events reported by the bridge.
-}
type Event
    = Closed (Maybe String)
    | Unknown String


{-| Ask the companion bridge to open a configuration URL.
-}
open : String -> String -> CommandEnvelope
open id url =
    Command.command id "configuration" "open"
        |> Command.withPayload (Encode.object [ ( "url", Encode.string url ) ])


{-| Subscribe to configuration close events.
-}
subscribe : String -> CommandEnvelope
subscribe id =
    Command.command id "configuration" "subscribe"


{-| Decode a bridge event into a configuration event.
-}
decode : BridgeEvent -> Event
decode bridgeEvent =
    case bridgeEvent.event of
        "configuration.closed" ->
            Closed
                (Decode.decodeValue (Decode.maybe (Decode.field "response" Decode.string)) bridgeEvent.payload
                    |> Result.withDefault Nothing
                )

        other ->
            Unknown other
