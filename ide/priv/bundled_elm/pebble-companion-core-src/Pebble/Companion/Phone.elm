port module Pebble.Companion.Phone exposing
    ( decodeWatchToPhone
    , onWatchToPhone
    , platformIncomingFor
    , sendPhoneToWatch
    )

{-| Watch AppMessage protocol wiring and per-API platform incoming ports.

Use the typed `Pebble.Companion.*` modules for phone platform APIs such as
weather, storage, and battery. Each platform API registers its own incoming
port so apps can compose listeners with plain `Sub.batch`.

This module is for typed watch ↔ phone AppMessage traffic and platform bridge
ports only.

Message constructors such as `WatchToPhone` and `PhoneToWatch` come from your
project's protocol definition in `protocol/src/Companion/Types.elm`.

    import Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))
    import Pebble.Companion.Battery as Battery
    import Pebble.Companion.Locale as Locale
    import Pebble.Companion.Phone as Phone

    type Msg
        = FromWatch (Result String WatchToPhone)
        | GotBattery (Result String Battery.BatteryInfo)
        | GotLocale (Result String Locale.LocaleInfo)

    subscriptions _ =
        Sub.batch
            [ Phone.onWatchToPhone FromWatch
            , Battery.onBattery GotBattery
            , Locale.onLocale GotLocale
            ]

# Watch protocol

@docs decodeWatchToPhone, onWatchToPhone, sendPhoneToWatch

# Platform ports

@docs platformIncomingFor

-}

import Companion.Internal as Internal
import Companion.Types exposing (PhoneToWatch, WatchToPhone)
import Json.Decode as Decode
import Json.Encode as Encode
import Pebble.Companion.AppMessage as AppMessage
import Pebble.Companion.Codec as Codec
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (CommandEnvelope)
import Sub


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


port batteryPlatformIncoming : (Decode.Value -> msg) -> Sub msg


port localePlatformIncoming : (Decode.Value -> msg) -> Sub msg


port connectivityPlatformIncoming : (Decode.Value -> msg) -> Sub msg


port notificationsPlatformIncoming : (Decode.Value -> msg) -> Sub msg


port weatherPlatformIncoming : (Decode.Value -> msg) -> Sub msg


port weatherCurrentPlatformIncoming : (Decode.Value -> msg) -> Sub msg


port weatherForecastPlatformIncoming : (Decode.Value -> msg) -> Sub msg


port calendarPlatformIncoming : (Decode.Value -> msg) -> Sub msg


port calendarUpcomingPlatformIncoming : (Decode.Value -> msg) -> Sub msg


port calendarNextPlatformIncoming : (Decode.Value -> msg) -> Sub msg


port environmentPlatformIncoming : (Decode.Value -> msg) -> Sub msg


port storagePlatformIncoming : (Decode.Value -> msg) -> Sub msg


port preferencesPlatformIncoming : (Decode.Value -> msg) -> Sub msg


port configurationPlatformIncoming : (Decode.Value -> msg) -> Sub msg


port webSocketPlatformIncoming : (Decode.Value -> msg) -> Sub msg


port webSocketCommandsPlatformIncoming : (Decode.Value -> msg) -> Sub msg


port lifecyclePlatformIncoming : (Decode.Value -> msg) -> Sub msg


port timelineTokenPlatformIncoming : (Decode.Value -> msg) -> Sub msg


port timelineCommandsPlatformIncoming : (Decode.Value -> msg) -> Sub msg


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


{-| Route a platform handler id to its dedicated incoming port.
-}
platformIncomingFor : String -> (Decode.Value -> msg) -> Sub msg
platformIncomingFor handlerId toMsg =
    case handlerId of
        "battery" ->
            batteryPlatformIncoming toMsg

        "locale" ->
            localePlatformIncoming toMsg

        "connectivity" ->
            connectivityPlatformIncoming toMsg

        "notifications" ->
            notificationsPlatformIncoming toMsg

        "weather" ->
            weatherPlatformIncoming toMsg

        "weather-current" ->
            weatherCurrentPlatformIncoming toMsg

        "weather-forecast" ->
            weatherForecastPlatformIncoming toMsg

        "calendar" ->
            calendarPlatformIncoming toMsg

        "calendar-upcoming" ->
            calendarUpcomingPlatformIncoming toMsg

        "calendar-next" ->
            calendarNextPlatformIncoming toMsg

        "environment" ->
            environmentPlatformIncoming toMsg

        "storage" ->
            storagePlatformIncoming toMsg

        "preferences" ->
            preferencesPlatformIncoming toMsg

        "configuration" ->
            configurationPlatformIncoming toMsg

        "webSocket" ->
            webSocketPlatformIncoming toMsg

        "webSocket-commands" ->
            webSocketCommandsPlatformIncoming toMsg

        "lifecycle" ->
            lifecyclePlatformIncoming toMsg

        "timeline-token" ->
            timelineTokenPlatformIncoming toMsg

        "timeline-commands" ->
            timelineCommandsPlatformIncoming toMsg

        _ ->
            Sub.none


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
