module Pebble.Companion.Battery exposing (BatteryInfo, Event(..), decode, status, subscribe)

{-| Phone battery information exposed by the companion bridge.

# Types
@docs BatteryInfo, Event

# Commands
@docs status, subscribe

# Events
@docs decode

-}

import Json.Decode as Decode
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (BridgeEvent, CommandEnvelope)


{-| Current phone battery charge and charging state.
-}
type alias BatteryInfo =
    { percent : Int
    , charging : Bool
    }


{-| Battery events emitted by the companion bridge.
-}
type Event
    = Status BatteryInfo
    | Error String
    | Unknown String


{-| Request the current phone battery status.
-}
status : String -> CommandEnvelope
status id =
    Command.command id "battery" "status"


{-| Subscribe to phone battery status changes when supported.
-}
subscribe : String -> CommandEnvelope
subscribe id =
    Command.command id "battery" "subscribe"


{-| Decode a pushed battery bridge event.
-}
decode : BridgeEvent -> Event
decode bridgeEvent =
    case bridgeEvent.event of
        "battery.status" ->
            decodePayload decodeBatteryInfo bridgeEvent.payload
                |> Result.map Status
                |> Result.withDefault (Error "Invalid battery status payload")

        "battery.error" ->
            Error (decodeErrorMessage bridgeEvent.payload "Battery information unavailable")

        other ->
            Unknown other


decodeBatteryInfo : Decode.Decoder BatteryInfo
decodeBatteryInfo =
    Decode.map2 BatteryInfo
        (Decode.field "percent" Decode.int)
        (Decode.field "charging" Decode.bool)


decodePayload : Decode.Decoder a -> Decode.Value -> Result Decode.Error a
decodePayload decoder value =
    Decode.decodeValue decoder value


decodeErrorMessage : Decode.Value -> String -> String
decodeErrorMessage payload fallback =
    Decode.decodeValue (Decode.field "message" Decode.string) payload
        |> Result.withDefault fallback
