port module Companion.Phone exposing (decodeWatchToPhone, onRawMessage, onWatchToPhone, sendBridgeCommand, sendPhoneToWatch)

{-| Companion-side API for receiving watch requests and sending responses. -}

import Companion.Internal as Internal
import Companion.Types exposing (PhoneToWatch, WatchToPhone)
import Json.Decode as Decode
import Json.Encode as Encode
import Pebble.Companion.AppMessage as AppMessage
import Pebble.Companion.Codec as Codec
import Pebble.Companion.Contract exposing (CommandEnvelope)


port incoming : (Decode.Value -> msg) -> Sub msg


port outgoing : Encode.Value -> Cmd msg


{-| Decode a watch-originated request payload into a typed message. -}
decodeWatchToPhone : Decode.Value -> Result String WatchToPhone
decodeWatchToPhone =
    Internal.decodeWatchToPhonePayload


{-| Subscribe to watch-originated AppMessage payloads as typed protocol messages. -}
onWatchToPhone : (Result String WatchToPhone -> msg) -> Sub msg
onWatchToPhone toMsg =
    incoming (decodeIncomingPayload >> Result.andThen decodeWatchToPhone >> toMsg)


{-| Subscribe to raw bridge events from the JavaScript companion bridge.

This is useful for generated helper modules that need to observe non-AppMessage
events, such as companion configuration responses.
-}
onRawMessage : (Decode.Value -> msg) -> Sub msg
onRawMessage =
    incoming


{-| Encode and send a typed phone-to-watch response. -}
sendPhoneToWatch : PhoneToWatch -> Cmd msg
sendPhoneToWatch message =
    AppMessage.send "phone-to-watch" (Internal.encodePhoneToWatch message)
        |> Codec.encodeCommand
        |> outgoing


{-| Send a generic command envelope to the JavaScript companion bridge. -}
sendBridgeCommand : CommandEnvelope -> Cmd msg
sendBridgeCommand command =
    Codec.encodeCommand command
        |> outgoing


decodeIncomingPayload : Decode.Value -> Result String Decode.Value
decodeIncomingPayload payload =
    case Decode.decodeValue Codec.decodeEvent payload of
        Ok event ->
            AppMessage.decodeIncoming event

        Err _ ->
            Ok payload
