port module Pebble.Companion.Phone exposing
    ( Request(..)
    , decodeWatchToPhone
    , onRawMessage
    , onWatchToPhone
    , request
    , requestWithPayload
    , send
    , sendBridgeCommand
    , sendPhoneToWatch
    , sendRequest
    , subscribeBridge
    )

{-| Companion-side bridge for watch protocol messages and platform APIs.

Use the typed `Pebble.Companion.*` modules for weather, storage, and other
platform capabilities. This module handles the JavaScript bridge ports and
watch AppMessage protocol wiring.

# Watch protocol

@docs decodeWatchToPhone, onWatchToPhone, sendPhoneToWatch

# Platform requests

@docs Request(..), request, requestWithPayload, send, sendRequest

# Low-level bridge

@docs sendBridgeCommand, subscribeBridge, onRawMessage

-}

import Companion.Internal as Internal
import Companion.Types exposing (PhoneToWatch, WatchToPhone)
import Json.Decode as Decode
import Json.Encode as Encode
import Pebble.Companion.AppMessage as AppMessage
import Pebble.Companion.Codec as Codec
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (CommandEnvelope)


{-| A bridge command plus a decoder for its response payload.
-}
type Request a
    = Request CommandEnvelope (Decode.Value -> Result String a)


{-| Build a request for a bridge command.
-}
request : String -> String -> String -> (Decode.Value -> Result String a) -> Request a
request id api op decodeResponse =
    Request (Command.command id api op) decodeResponse


{-| Build a request for a bridge command with a JSON payload.
-}
requestWithPayload :
    String
    -> String
    -> String
    -> Encode.Value
    -> (Decode.Value -> Result String a)
    -> Request a
requestWithPayload id api op payload decodeResponse =
    Request (Command.command id api op |> Command.withPayload payload) decodeResponse


{-| Send a bridge request and deliver the decoded response to `toMsg`.
-}
send : (Result String a -> msg) -> Request a -> Cmd msg
send toMsg (Request envelope decodeResponse) =
    sendRequest envelope decodeResponse toMsg


{-| Send a bridge request and deliver the decoded response to `toMsg`.

The JavaScript bridge stores `decodeResponse` and `toMsg` until the matching
response arrives, then enqueues the resulting message in the Elm runtime.
-}
sendRequest :
    CommandEnvelope
    -> (Decode.Value -> Result String a)
    -> (Result String a -> msg)
    -> Cmd msg
sendRequest envelope decodeResponse toMsg =
    Cmd.batch
        [ registerResponseHandler envelope.id decodeResponse toMsg
        , sendBridgeCommand envelope
        ]


port incoming : (Decode.Value -> msg) -> Sub msg


port outgoing : Encode.Value -> Cmd msg


port bridgeInterest : Encode.Value -> Sub msg


{-| Tell the bridge to push updates while this subscription is active.
-}
subscribeBridge : CommandEnvelope -> Sub msg
subscribeBridge envelope =
    bridgeInterest (Codec.encodeCommand envelope)


{-| Decode a watch-originated request payload into a typed message. -}
decodeWatchToPhone : Decode.Value -> Result String WatchToPhone
decodeWatchToPhone =
    Internal.decodeWatchToPhonePayload


{-| Subscribe to watch-originated AppMessage payloads as typed protocol messages. -}
onWatchToPhone : (Result String WatchToPhone -> msg) -> Sub msg
onWatchToPhone toMsg =
    incoming (decodeIncomingPayload >> Result.andThen decodeWatchToPhone >> toMsg)


{-| Subscribe to raw bridge messages from the JavaScript companion bridge. -}
onRawMessage : (Decode.Value -> msg) -> Sub msg
onRawMessage =
    incoming


{-| Encode and send a typed phone-to-watch response. -}
sendPhoneToWatch : PhoneToWatch -> Cmd msg
sendPhoneToWatch message =
    AppMessage.send "phone-to-watch" (Internal.encodePhoneToWatch message)
        |> Codec.encodeCommand
        |> outgoing


{-| Send a command envelope to the JavaScript companion bridge. -}
sendBridgeCommand : CommandEnvelope -> Cmd msg
sendBridgeCommand command =
    Codec.encodeCommand command
        |> outgoing


registerResponseHandler :
    String
    -> (Decode.Value -> Result String a)
    -> (Result String a -> msg)
    -> Cmd msg
registerResponseHandler id decodeResponse toMsg =
    let
        _ =
            ( id, decodeResponse, toMsg )
    in
    outgoing <|
        Encode.object
            [ ( "registerBridgeResponse", Encode.string id )
            ]


decodeIncomingPayload : Decode.Value -> Result String Decode.Value
decodeIncomingPayload payload =
    case Decode.decodeValue Codec.decodeEvent payload of
        Ok event ->
            AppMessage.decodeIncoming event

        Err _ ->
            Ok payload
