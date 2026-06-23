module Pebble.System exposing (batteryLevel, connectionStatus, onBatteryChange, onConnectionChange)

import Elm.Kernel.PebbleWatch

{-| System-state commands and subscriptions sourced from Pebble event services.

Poll once in `init`, then subscribe to live updates for battery and phone link.

    import Pebble.System as System

    type Msg
        = GotBattery Int
        | BatteryChanged Int
        | GotConnection Bool
        | ConnectionChanged Bool

    init _ =
        ( model
        , Cmd.batch
            [ System.batteryLevel GotBattery
            , System.connectionStatus GotConnection
            ]
        )

    subscriptions _ =
        Sub.batch
            [ System.onBatteryChange BatteryChanged
            , System.onConnectionChange ConnectionChanged
            ]

For a runnable example, use the **watch-demo-system** project template in the IDE.

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
