module Pebble.System exposing (batteryLevel, connectionStatus, onBatteryChange, onConnectionChange)

import Elm.Kernel.PebbleWatch

{-| System-state subscriptions sourced from Pebble event services.

@docs batteryLevel, connectionStatus, onBatteryChange, onConnectionChange
-}


{-| Request the current battery level as a percentage from 0 to 100. -}
batteryLevel : (Int -> msg) -> Cmd msg
batteryLevel =
    Elm.Kernel.PebbleWatch.getBatteryLevel


{-| Request whether the watch is connected to the phone. -}
connectionStatus : (Bool -> msg) -> Cmd msg
connectionStatus =
    Elm.Kernel.PebbleWatch.getConnectionStatus


{-| Receive the current battery percentage when battery state changes.
-}
onBatteryChange : (Int -> msg) -> Sub msg
onBatteryChange =
    Elm.Kernel.PebbleWatch.onBatteryChange


{-| Receive whether the watch is connected to the phone when connection state changes.
-}
onConnectionChange : (Bool -> msg) -> Sub msg
onConnectionChange =
    Elm.Kernel.PebbleWatch.onConnectionChange
