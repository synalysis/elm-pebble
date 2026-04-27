module Pebble.Companion.WebSocket exposing
    ( Event(..)
    , connect
    , decode
    , disconnect
    , send
    , subscribe
    )

{-| WebSocket commands and events through the phone companion bridge.

    Pebble.Companion.WebSocket.connect "socket-connect" "wss://example.com/live"

# Events
@docs Event, decode

# Commands
@docs connect, disconnect, send, subscribe

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (BridgeEvent, CommandEnvelope)


{-| WebSocket events emitted by the companion bridge.
-}
type Event
    = Opened
    | Closed (Maybe Int)
    | Message String
    | Error String
    | Unknown String


{-| Open a WebSocket connection.
-}
connect : String -> String -> CommandEnvelope
connect id url =
    Command.command id "webSocket" "connect"
        |> Command.withPayload (Encode.object [ ( "url", Encode.string url ) ])


{-| Close the active WebSocket connection.
-}
disconnect : String -> CommandEnvelope
disconnect id =
    Command.command id "webSocket" "disconnect"


{-| Send a string message over the active WebSocket.
-}
send : String -> String -> CommandEnvelope
send id message =
    Command.command id "webSocket" "send"
        |> Command.withPayload (Encode.object [ ( "message", Encode.string message ) ])


{-| Subscribe to WebSocket events.
-}
subscribe : String -> CommandEnvelope
subscribe id =
    Command.command id "webSocket" "subscribe"


{-| Decode a bridge WebSocket event.
-}
decode : BridgeEvent -> Event
decode bridgeEvent =
    case bridgeEvent.event of
        "webSocket.open" ->
            Opened

        "webSocket.close" ->
            Closed
                (Decode.decodeValue (Decode.maybe (Decode.field "code" Decode.int)) bridgeEvent.payload
                    |> Result.withDefault Nothing
                )

        "webSocket.message" ->
            Message
                (Decode.decodeValue (Decode.field "data" Decode.string) bridgeEvent.payload
                    |> Result.withDefault ""
                )

        "webSocket.error" ->
            Error
                (Decode.decodeValue (Decode.field "message" Decode.string) bridgeEvent.payload
                    |> Result.withDefault "Unknown websocket error"
                )

        other ->
            Unknown other
