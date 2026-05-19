module Companion.Battery exposing (BatteryInfo, current, onBattery, subscribe)

{-| Phone battery helpers for companion apps. -}

import Companion.Phone as Phone
import Json.Decode as Decode
import Pebble.Companion.Battery as Battery
import Pebble.Companion.Codec as Codec


type alias BatteryInfo =
    Battery.BatteryInfo


current : Cmd msg
current =
    Battery.status "battery-status"
        |> Phone.sendBridgeCommand


subscribe : Cmd msg
subscribe =
    Battery.subscribe "battery-subscribe"
        |> Phone.sendBridgeCommand


onBattery : (Result String BatteryInfo -> msg) -> Sub msg
onBattery toMsg =
    Phone.onRawMessage (decodeBattery >> toMsg)


decodeBattery : Decode.Value -> Result String BatteryInfo
decodeBattery value =
    case Decode.decodeValue Codec.decodeEvent value of
        Ok event ->
            case Battery.decode event of
                Battery.Status info ->
                    Ok info

                Battery.Error error ->
                    Err error

                Battery.Unknown eventName ->
                    Err ("Unexpected battery event: " ++ eventName)

        Err error ->
            Err (Decode.errorToString error)
