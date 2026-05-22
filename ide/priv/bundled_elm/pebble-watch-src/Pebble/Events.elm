module Pebble.Events exposing
    ( batch
    , onDayChange
    , onHourChange
    , onMinuteChange
    , onMonthChange
    , onSecondChange
    , onYearChange
    )


{-| Generic watch-side event subscriptions.

Each helper turns a platform event into a regular Elm `Sub msg`.

# Time
@docs onSecondChange, onMinuteChange, onHourChange, onDayChange, onMonthChange, onYearChange

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


{-| Receive a message when the local hour changes.

The value is the current wall-clock hour, from `0` to `23`.
-}
onHourChange : (Int -> msg) -> Sub msg
onHourChange =
    Elm.Kernel.PebbleWatch.onHourChange


{-| Receive a message when the local minute changes.

The value is the current wall-clock minute, from `0` to `59`.
-}
onMinuteChange : (Int -> msg) -> Sub msg
onMinuteChange =
    Elm.Kernel.PebbleWatch.onMinuteChange


{-| Receive a message when the local day of month changes.

The value is the current day of month, from `1` to `31`.
-}
onDayChange : (Int -> msg) -> Sub msg
onDayChange =
    Elm.Kernel.PebbleWatch.onDayChange


{-| Receive a message when the local month changes.

The value is the current month number, from `1` to `12`.
-}
onMonthChange : (Int -> msg) -> Sub msg
onMonthChange =
    Elm.Kernel.PebbleWatch.onMonthChange


{-| Receive a message when the local year changes.

The value is the current full year, for example `2026`.
-}
onYearChange : (Int -> msg) -> Sub msg
onYearChange =
    Elm.Kernel.PebbleWatch.onYearChange


{-| Combine multiple Pebble subscriptions into one.
-}
batch : List (Sub msg) -> Sub msg
batch =
    Elm.Kernel.PebbleWatch.batch
