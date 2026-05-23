module Pebble.Companion.Battery exposing
    ( BatteryInfo
    , current
    , onBattery
    , setup
    )

{-| Phone battery helpers for companion apps.

    init _ =
        ( model, Battery.current GotBattery )

    subscriptions _ =
        Battery.onBattery GotBattery

# Types

@docs BatteryInfo

# Commands

@docs current, setup

# Subscriptions

@docs onBattery

-}

import Json.Decode as Decode
import Pebble.Companion.Codec as Codec
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (BridgeEvent)
import Pebble.Companion.Phone as Phone
import Pebble.Companion.Platform as Platform


{-| Current phone battery charge and charging state.
-}
type alias BatteryInfo =
    { percent : Int
    , charging : Bool
    }


{-| Request the current phone battery status.
-}
current : (Result String BatteryInfo -> msg) -> Cmd msg
current toMsg =
    Phone.send toMsg <|
        Phone.request "battery-status" "battery" "status" decodeResponse


{-| Receive pushed battery status updates from the companion bridge.

Registering this subscription also tells the bridge to send battery updates.
-}
onBattery : (Result String BatteryInfo -> msg) -> Sub msg
onBattery toMsg =
    Platform.subscribe (handler toMsg)


{-| Register the battery platform handler with the companion bridge.
-}
setup : Cmd msg
setup =
    Platform.setup batteryInterest


{-| Platform router handler for battery events and responses.
-}
handler toMsg =
    Platform.handler batteryInterest decodeBattery toMsg


batteryInterest =
    Platform.interest
        { id = "battery"
        , subscribeCommand =
            Just <|
                Command.command "battery-subscribe" "battery" "subscribe"
        , eventPrefixes = [ "battery." ]
        , resultIdPrefixes = [ "battery-" ]
        }


decodeResponse : Decode.Value -> Result String BatteryInfo
decodeResponse value =
    decodeBattery value


decodeBattery : Decode.Value -> Result String BatteryInfo
decodeBattery value =
    case Decode.decodeValue Codec.decodeEvent value of
        Ok event ->
            decodeBridgeEvent event

        Err _ ->
            decodeBridgeResult value


decodeBridgeResult : Decode.Value -> Result String BatteryInfo
decodeBridgeResult value =
    case Decode.decodeValue Codec.decodeResult value of
        Ok envelope ->
            if envelope.ok then
                case envelope.payload of
                    Nothing ->
                        Err "Battery response missing payload"

                    Just payload ->
                        decodeBridgeEvent { event = "battery.status", payload = payload }

            else
                Err (decodeBridgeError envelope)

        Err error ->
            Err (Decode.errorToString error)


decodeBridgeEvent : BridgeEvent -> Result String BatteryInfo
decodeBridgeEvent bridgeEvent =
    case bridgeEvent.event of
        "battery.status" ->
            Decode.decodeValue decodeBatteryInfo bridgeEvent.payload
                |> Result.mapError Decode.errorToString

        "battery.error" ->
            Err (decodeErrorMessage bridgeEvent.payload "Battery information unavailable")

        other ->
            Err ("Unexpected battery event: " ++ other)


decodeBatteryInfo : Decode.Decoder BatteryInfo
decodeBatteryInfo =
    Decode.map2 BatteryInfo
        (Decode.field "percent" Decode.int)
        (Decode.field "charging" Decode.bool)


decodeBridgeError : Pebble.Companion.Contract.ResultEnvelope -> String
decodeBridgeError envelope =
    case envelope.error of
        Just error ->
            error.message

        Nothing ->
            "Battery information unavailable"


decodeErrorMessage : Decode.Value -> String -> String
decodeErrorMessage payload fallback =
    Decode.decodeValue (Decode.field "message" Decode.string) payload
        |> Result.withDefault fallback
