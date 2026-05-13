module Pebble.Events exposing
    ( batch
    , onHourChange
    , onMinuteChange
    , onSecondChange
    , onTick
    )


{-| Generic watch-side event subscriptions.

Each helper turns a platform event into a regular Elm `Sub msg`.

# Time
@docs onSecondChange, onHourChange, onMinuteChange

# Composition
@docs batch

-}


import Elm.Kernel.PebbleWatch


{-| Receive the current second whenever the local second changes.

The value is the current wall-clock second, from `0` to `59`.
-}
onSecondChange : (Int -> msg) -> Sub msg
onSecondChange =
    Elm.Kernel.PebbleWatch.onSecondChange


{-| Backward-compatible alias for `onSecondChange`.
-}
onTick : (Int -> msg) -> Sub msg
onTick =
    onSecondChange


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
