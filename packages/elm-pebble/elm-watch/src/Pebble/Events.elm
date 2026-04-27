module Pebble.Events exposing
    ( batch
    , onAccelTap
    , onButtonDown
    , onButtonLongDown
    , onButtonLongSelect
    , onButtonLongUp
    , onButtonSelect
    , onButtonUp
    , onHourChange
    , onMinuteChange
    , onTick
    )


{-| Subscriptions for watch-side hardware and button events.

Each helper turns a platform event into a regular Elm `Sub msg`.

# Tick
@docs onTick, onHourChange, onMinuteChange

# Buttons
@docs onButtonUp, onButtonSelect, onButtonDown, onButtonLongUp, onButtonLongSelect, onButtonLongDown

# Sensors
@docs onAccelTap

# Composition
@docs batch

-}


import Elm.Kernel.PebbleWatch


{-| Receive the current second on each clock tick from the runtime.

The value is the current wall-clock second, from `0` to `59`.
-}
onTick : (Int -> msg) -> Sub msg
onTick =
    Elm.Kernel.PebbleWatch.onTick


{-| Receive a message when the local hour changes.
-}
onHourChange : (Int -> msg) -> Sub msg
onHourChange =
    Elm.Kernel.PebbleWatch.onHourChange


{-| Receive a message when the local minute changes.
-}
onMinuteChange : (Int -> msg) -> Sub msg
onMinuteChange =
    Elm.Kernel.PebbleWatch.onMinuteChange


{-| Receive a message when the Up button is pressed.
-}
onButtonUp : msg -> Sub msg
onButtonUp =
    Elm.Kernel.PebbleWatch.onButtonUp


{-| Receive a message when the Select button is pressed.
-}
onButtonSelect : msg -> Sub msg
onButtonSelect =
    Elm.Kernel.PebbleWatch.onButtonSelect


{-| Receive a message when the Down button is pressed.
-}
onButtonDown : msg -> Sub msg
onButtonDown =
    Elm.Kernel.PebbleWatch.onButtonDown


{-| Receive a message when an accelerometer tap gesture fires.
-}
onAccelTap : msg -> Sub msg
onAccelTap =
    Elm.Kernel.PebbleWatch.onAccelTap


{-| Receive a message when the Up button is long-pressed.
-}
onButtonLongUp : msg -> Sub msg
onButtonLongUp =
    Elm.Kernel.PebbleWatch.onButtonLongUp


{-| Receive a message when the Select button is long-pressed.
-}
onButtonLongSelect : msg -> Sub msg
onButtonLongSelect =
    Elm.Kernel.PebbleWatch.onButtonLongSelect


{-| Receive a message when the Down button is long-pressed.
-}
onButtonLongDown : msg -> Sub msg
onButtonLongDown =
    Elm.Kernel.PebbleWatch.onButtonLongDown


{-| Combine multiple Pebble subscriptions into one.
-}
batch : List (Sub msg) -> Sub msg
batch =
    Elm.Kernel.PebbleWatch.batch
