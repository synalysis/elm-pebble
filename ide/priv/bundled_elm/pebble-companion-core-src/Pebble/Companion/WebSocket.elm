module Pebble.Companion.WebSocket exposing
    ( Event(..)
    , connect
    , disconnect
    , onWebSocket
    , onCommands
    , send
    , setup
    , setupCommands
    )

{-| WebSocket commands and events through the phone companion bridge.

    init _ =
        ( model, WebSocket.connect "wss://example.com/live" Connected )

    subscriptions _ =
        WebSocket.onWebSocket WebSocketChanged

# Events

@docs Event

# Commands

@docs connect, disconnect, send

# Subscriptions

@docs onWebSocket, onCommands

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Pebble.Companion.Codec as Codec
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (BridgeEvent)
import Pebble.Companion.Phone as Phone
import Pebble.Companion.Platform as Platform


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
connect : String -> (Result String () -> msg) -> Cmd msg
connect url toMsg =
    Phone.send toMsg <|
        Phone.requestWithPayload "webSocket-connect" "webSocket" "connect"
            (Encode.object [ ( "url", Encode.string url ) ])
            decodeCommandResponse


{-| Close the active WebSocket connection.
-}
disconnect : (Result String () -> msg) -> Cmd msg
disconnect toMsg =
    Phone.send toMsg <|
        Phone.request "webSocket-disconnect" "webSocket" "disconnect" decodeCommandResponse


{-| Send a string message over the active WebSocket.
-}
send : String -> (Result String () -> msg) -> Cmd msg
send message toMsg =
    Phone.send toMsg <|
        Phone.requestWithPayload "webSocket-send" "webSocket" "send"
            (Encode.object [ ( "message", Encode.string message ) ])
            decodeCommandResponse


{-| Receive pushed WebSocket events from the companion bridge.

Registering this subscription also tells the bridge to send WebSocket updates.
-}
onWebSocket : (Event -> msg) -> Sub msg
onWebSocket toMsg =
    Platform.subscribe (handler toMsg)


{-| Receive WebSocket command responses on the dedicated WebSocket port.
-}
onCommands : (Result String () -> msg) -> Sub msg
onCommands toMsg =
    Platform.subscribe (handlerCommands toMsg)


setup : Cmd msg
setup =
    Platform.setup webSocketInterest


setupCommands : Cmd msg
setupCommands =
    Platform.setup webSocketCommandInterest


handler toMsg =
    Platform.handler webSocketInterest decodeWebSocketEvent <|
        Result.withDefault (Unknown "webSocket decode failed") >> toMsg


handlerCommands toMsg =
    Platform.handler webSocketCommandInterest decodeCommandResponse toMsg


webSocketCommandInterest =
    Platform.interest
        { id = "webSocket-commands"
        , subscribeCommand = Nothing
        , eventPrefixes = []
        , resultIdPrefixes = [ "webSocket-" ]
        }


webSocketInterest =
    Platform.interest
        { id = "webSocket"
        , subscribeCommand =
            Just <|
                Command.command "webSocket-subscribe" "webSocket" "subscribe"
        , eventPrefixes = [ "webSocket." ]
        , resultIdPrefixes = []
        }


decodeCommandResponse : Decode.Value -> Result String ()
decodeCommandResponse value =
    case Decode.decodeValue Codec.decodeResult value of
        Ok envelope ->
            if envelope.ok then
                Ok ()

            else
                Err (decodeBridgeError envelope)

        Err error ->
            Err (Decode.errorToString error)


decodeWebSocketEvent : Decode.Value -> Result String Event
decodeWebSocketEvent value =
    case Decode.decodeValue Codec.decodeEvent value of
        Ok event ->
            Ok (decodeBridgeEvent event)

        Err error ->
            Err (Decode.errorToString error)


decodeBridgeEvent : BridgeEvent -> Event
decodeBridgeEvent bridgeEvent =
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


decodeBridgeError : Pebble.Companion.Contract.ResultEnvelope -> String
decodeBridgeError envelope =
    case envelope.error of
        Just error ->
            error.message

        Nothing ->
            "WebSocket command failed"
