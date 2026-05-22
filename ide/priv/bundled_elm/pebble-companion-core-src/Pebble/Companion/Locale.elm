module Pebble.Companion.Locale exposing
    ( LocaleInfo
    , current
    , onLocale
    )

{-| Phone locale and regional preference helpers for companion apps.

    init _ =
        ( model, Locale.current GotLocale )

# Types

@docs LocaleInfo

# Commands

@docs current

# Subscriptions

@docs onLocale

-}

import Json.Decode as Decode
import Pebble.Companion.Codec as Codec
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (BridgeEvent)
import Pebble.Companion.Phone as Phone
import Sub


{-| Phone locale, language, region, and clock-format preferences.
-}
type alias LocaleInfo =
    { locale : String
    , language : String
    , region : String
    , uses24h : Bool
    }


{-| Request the current phone locale status.
-}
current : (Result String LocaleInfo -> msg) -> Cmd msg
current toMsg =
    Phone.send toMsg <|
        Phone.request "locale-status" "locale" "status" decodeResponse


{-| Receive pushed locale status updates from the companion bridge.

Registering this subscription also tells the bridge to send locale updates.
-}
onLocale : (Result String LocaleInfo -> msg) -> Sub msg
onLocale toMsg =
    Sub.batch
        [ Phone.subscribeBridge <|
            Command.command "locale-subscribe" "locale" "subscribe"
        , Phone.onRawMessage (decodeLocale >> toMsg)
        ]


decodeResponse : Decode.Value -> Result String LocaleInfo
decodeResponse value =
    decodeLocale value


decodeLocale : Decode.Value -> Result String LocaleInfo
decodeLocale value =
    case Decode.decodeValue Codec.decodeEvent value of
        Ok event ->
            decodeBridgeEvent event

        Err _ ->
            decodeBridgeResult value


decodeBridgeResult : Decode.Value -> Result String LocaleInfo
decodeBridgeResult value =
    case Decode.decodeValue Codec.decodeResult value of
        Ok envelope ->
            if envelope.ok then
                case envelope.payload of
                    Nothing ->
                        Err "Locale response missing payload"

                    Just payload ->
                        decodeBridgeEvent { event = "locale.status", payload = payload }

            else
                Err (decodeBridgeError envelope)

        Err error ->
            Err (Decode.errorToString error)


decodeBridgeEvent : BridgeEvent -> Result String LocaleInfo
decodeBridgeEvent bridgeEvent =
    case bridgeEvent.event of
        "locale.status" ->
            Decode.decodeValue decodeLocaleInfo bridgeEvent.payload
                |> Result.mapError Decode.errorToString

        "locale.error" ->
            Err (decodeErrorMessage bridgeEvent.payload "Locale unavailable")

        other ->
            Err ("Unexpected locale event: " ++ other)


decodeLocaleInfo : Decode.Decoder LocaleInfo
decodeLocaleInfo =
    Decode.map4 LocaleInfo
        (Decode.field "locale" Decode.string)
        (Decode.field "language" Decode.string)
        (Decode.field "region" Decode.string)
        (Decode.field "uses24h" Decode.bool)


decodeBridgeError : Pebble.Companion.Contract.ResultEnvelope -> String
decodeBridgeError envelope =
    case envelope.error of
        Just error ->
            error.message

        Nothing ->
            "Locale unavailable"


decodeErrorMessage : Decode.Value -> String -> String
decodeErrorMessage payload fallback =
    Decode.decodeValue (Decode.field "message" Decode.string) payload
        |> Result.withDefault fallback
