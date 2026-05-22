module Pebble.Companion.Environment exposing
    ( EnvironmentInfo
    , MoonInfo
    , SunInfo
    , TideInfo
    , current
    , onEnvironment
    )

{-| Sun, moon, and tide environment helpers for companion apps.

    init _ =
        ( model, Environment.current GotEnvironment )

# Types

@docs SunInfo, MoonInfo, TideInfo, EnvironmentInfo

# Commands

@docs current

# Subscriptions

@docs onEnvironment

-}

import Json.Decode as Decode
import Pebble.Companion.Codec as Codec
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (BridgeEvent)
import Pebble.Companion.Phone as Phone
import Sub


{-| Sunrise, sunset, and polar-day information.
-}
type alias SunInfo =
    { sunriseMin : Int
    , sunsetMin : Int
    , polarDay : Bool
    }


{-| Moonrise, moonset, and phase information.
-}
type alias MoonInfo =
    { moonriseMin : Maybe Int
    , moonsetMin : Maybe Int
    , phaseE6 : Int
    }


{-| Next tide timing, level, and direction.
-}
type alias TideInfo =
    { nextMin : Int
    , levelCm : Int
    , rising : Bool
    }


{-| Combined sun, moon, and tide environment snapshot.
-}
type alias EnvironmentInfo =
    { sun : Maybe SunInfo
    , moon : Maybe MoonInfo
    , tide : Maybe TideInfo
    }


{-| Request the current environment snapshot.
-}
current : (Result String EnvironmentInfo -> msg) -> Cmd msg
current toMsg =
    Phone.send toMsg <|
        Phone.request "environment-current" "environment" "current" decodeResponse


{-| Subscribe to environment updates when supported.
-}
{-| Receive pushed environment updates from the companion bridge.

Registering this subscription also tells the bridge to send environment updates.
-}
onEnvironment : (Result String EnvironmentInfo -> msg) -> Sub msg
onEnvironment toMsg =
    Sub.batch
        [ Phone.subscribeBridge <|
            Command.command "environment-subscribe" "environment" "subscribe"
        , Phone.onRawMessage (decodeEnvironment >> toMsg)
        ]


decodeResponse : Decode.Value -> Result String EnvironmentInfo
decodeResponse value =
    decodeEnvironment value


decodeEnvironment : Decode.Value -> Result String EnvironmentInfo
decodeEnvironment value =
    case Decode.decodeValue Codec.decodeEvent value of
        Ok event ->
            decodeBridgeEvent event

        Err _ ->
            decodeBridgeResult value


decodeBridgeResult : Decode.Value -> Result String EnvironmentInfo
decodeBridgeResult value =
    case Decode.decodeValue Codec.decodeResult value of
        Ok envelope ->
            if envelope.ok then
                case envelope.payload of
                    Nothing ->
                        Err "Environment response missing payload"

                    Just payload ->
                        decodeBridgeEvent { event = "environment.current", payload = payload }

            else
                Err (decodeBridgeError envelope)

        Err error ->
            Err (Decode.errorToString error)


decodeBridgeEvent : BridgeEvent -> Result String EnvironmentInfo
decodeBridgeEvent bridgeEvent =
    case bridgeEvent.event of
        "environment.current" ->
            Decode.decodeValue decodeEnvironmentInfo bridgeEvent.payload
                |> Result.mapError Decode.errorToString

        "environment.error" ->
            Err (decodeErrorMessage bridgeEvent.payload "Environment unavailable")

        other ->
            Err ("Unexpected environment event: " ++ other)


decodeEnvironmentInfo : Decode.Decoder EnvironmentInfo
decodeEnvironmentInfo =
    Decode.map3 EnvironmentInfo
        (Decode.maybe (Decode.field "sun" decodeSunInfo))
        (Decode.maybe (Decode.field "moon" decodeMoonInfo))
        (Decode.maybe (Decode.field "tide" decodeTideInfo))


decodeSunInfo : Decode.Decoder SunInfo
decodeSunInfo =
    Decode.map3 SunInfo
        (Decode.field "sunriseMin" Decode.int)
        (Decode.field "sunsetMin" Decode.int)
        (Decode.field "polarDay" Decode.bool)


decodeMoonInfo : Decode.Decoder MoonInfo
decodeMoonInfo =
    Decode.map3 MoonInfo
        (Decode.maybe (Decode.field "moonriseMin" Decode.int))
        (Decode.maybe (Decode.field "moonsetMin" Decode.int))
        (Decode.field "phaseE6" Decode.int)


decodeTideInfo : Decode.Decoder TideInfo
decodeTideInfo =
    Decode.map3 TideInfo
        (Decode.field "nextMin" Decode.int)
        (Decode.field "levelCm" Decode.int)
        (Decode.field "rising" Decode.bool)


decodeBridgeError : Pebble.Companion.Contract.ResultEnvelope -> String
decodeBridgeError envelope =
    case envelope.error of
        Just error ->
            error.message

        Nothing ->
            "Environment unavailable"


decodeErrorMessage : Decode.Value -> String -> String
decodeErrorMessage payload fallback =
    Decode.decodeValue (Decode.field "message" Decode.string) payload
        |> Result.withDefault fallback
