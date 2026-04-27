module Pebble.Companion.Network exposing (Event(..), decode, status, subscribe)

{-| Query and observe phone network status.

    Pebble.Companion.Network.status "network-status"

# Events
@docs Event, decode

# Commands
@docs status, subscribe

-}

import Json.Decode as Decode
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (BridgeEvent, CommandEnvelope)


{-| Network status events from the companion bridge.
-}
type Event
    = StatusChanged Bool
    | Unknown String


{-| Request the current online/offline status.
-}
status : String -> CommandEnvelope
status id =
    Command.command id "network" "status"


{-| Subscribe to network status changes.
-}
subscribe : String -> CommandEnvelope
subscribe id =
    Command.command id "network" "subscribe"


{-| Decode a bridge network event.
-}
decode : BridgeEvent -> Event
decode bridgeEvent =
    case bridgeEvent.event of
        "network.status" ->
            StatusChanged
                (Decode.decodeValue (Decode.field "online" Decode.bool) bridgeEvent.payload
                    |> Result.withDefault False
                )

        other ->
            Unknown other
