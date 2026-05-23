port module Pebble.Companion.Phone exposing
    ( decodeWatchToPhone
    , onWatchToPhone
    , sendPhoneToWatch
    )

{-| Watch AppMessage protocol wiring for companion apps.

Use the typed `Pebble.Companion.*` modules for phone platform APIs such as
weather, storage, and battery. This module is for typed watch ↔ phone
AppMessage traffic only.

Message constructors such as `WatchToPhone` and `PhoneToWatch` come from your
project's protocol definition in `protocol/src/Companion/Types.elm`.

    import Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))
    import Pebble.Companion.Phone as Phone

    type Msg
        = FromWatch (Result String WatchToPhone)

    subscriptions _ =
        Phone.onWatchToPhone FromWatch

    update msg model =
        case msg of
            FromWatch (Ok RequestFigure) ->
                ( model, Phone.sendPhoneToWatch (ProvideFigure 0) )

            FromWatch (Err _) ->
                ( model, Cmd.none )

# Watch protocol

@docs decodeWatchToPhone, onWatchToPhone, sendPhoneToWatch

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


request : String -> String -> String -> (Decode.Value -> Result String a) -> Request a
request id api op decodeResponse =
    Request (Command.command id api op) decodeResponse


requestWithPayload :
    String
    -> String
    -> String
    -> Encode.Value
    -> (Decode.Value -> Result String a)
    -> Request a
requestWithPayload id api op payload decodeResponse =
    Request (Command.command id api op |> Command.withPayload payload) decodeResponse


send : (Result String a -> msg) -> Request a -> Cmd msg
send toMsg (Request envelope decodeResponse) =
    sendRequest envelope decodeResponse toMsg


sendRequest :
    CommandEnvelope
    -> (Decode.Value -> Result String a)
    -> (Result String a -> msg)
    -> Cmd msg
sendRequest envelope decodeResponse toMsg =
    Cmd.batch
        [ registerResponseHandler envelope.id
        , sendBridgeCommand envelope
        ]


port incoming : (Decode.Value -> msg) -> Sub msg


port platformIncoming : (Decode.Value -> msg) -> Sub msg


port outgoing : Encode.Value -> Cmd msg


port bridgeInterest : Encode.Value -> Sub msg


port registerPlatformHandler : Encode.Value -> Sub msg


registerHandler : String -> Encode.Value -> Sub msg
registerHandler handlerId interest =
    registerPlatformHandler <|
        Encode.object
            [ ( "handlerId", Encode.string handlerId )
            , ( "interest", interest )
            , ( "active", Encode.bool True )
            ]


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


onRawMessage : (Decode.Value -> msg) -> Sub msg
onRawMessage =
    incoming


{-| Encode and send a typed phone-to-watch response. -}
sendPhoneToWatch : PhoneToWatch -> Cmd msg
sendPhoneToWatch message =
    AppMessage.send "phone-to-watch" (Internal.encodePhoneToWatch message)
        |> Codec.encodeCommand
        |> outgoing


sendBridgeCommand : CommandEnvelope -> Cmd msg
sendBridgeCommand command =
    Codec.encodeCommand command
        |> outgoing


registerResponseHandler : String -> Cmd msg
registerResponseHandler id =
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
