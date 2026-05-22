module Pebble.Companion.Lifecycle exposing (Event(..), decode, subscribe)

{-| Observe phone companion lifecycle events.

Subscribe once during companion startup and route pushed bridge events through
`decode`.

# Events
@docs Event, decode

# Commands
@docs subscribe

-}

import Json.Decode as Decode
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (BridgeEvent, CommandEnvelope)


{-| Lifecycle events emitted by the companion bridge.
-}
type Event
    = Ready
    | ShowConfiguration
    | WebViewClosed (Maybe String)
    | VisibilityChanged Bool
    | Unknown String


{-| Subscribe to lifecycle events.
-}
subscribe : String -> CommandEnvelope
subscribe id =
    Command.command id "lifecycle" "subscribe"


{-| Decode a bridge lifecycle event.
-}
decode : BridgeEvent -> Event
decode bridgeEvent =
    case bridgeEvent.event of
        "lifecycle.ready" ->
            Ready

        "lifecycle.showConfiguration" ->
            ShowConfiguration

        "lifecycle.webviewclosed" ->
            WebViewClosed
                (Decode.decodeValue (Decode.maybe (Decode.field "response" Decode.string)) bridgeEvent.payload
                    |> Result.withDefault Nothing
                )

        "lifecycle.visibility" ->
            VisibilityChanged
                (Decode.decodeValue (Decode.field "visible" Decode.bool) bridgeEvent.payload
                    |> Result.withDefault True
                )

        other ->
            Unknown other
