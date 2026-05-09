module Pebble.Events exposing
    ( batch
    , onHourChange
    , onMinuteChange
    , onTick
    )


{-| Generic watch-side event subscriptions.

Each helper turns a platform event into a regular Elm `Sub msg`.

# Tick
@docs onTick, onHourChange, onMinuteChange

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


{-| Combine multiple Pebble subscriptions into one.
-}
batch : List (Sub msg) -> Sub msg
batch =
    Elm.Kernel.PebbleWatch.batch
