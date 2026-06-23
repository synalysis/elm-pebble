module Pebble.Events exposing
    ( batch
    , onAnimationFinished
    , onDayChange
    , onHourChange
    , onMinuteChange
    , onMonthChange
    , onSecondChange
    , onYearChange
    )


{-| Generic watch-side event subscriptions.

Each helper turns a platform event into a regular Elm `Sub msg`.
Use `batch` to combine time ticks with other Pebble subscriptions.

    import Pebble.Events as Events

    type Msg
        = MinuteChanged Int
        | HourChanged Int

    subscriptions _ =
        Events.batch
            [ Events.onMinuteChange MinuteChanged
            , Events.onHourChange HourChanged
            ]

Watchfaces often use `onMinuteChange` to refresh the clock each minute.

# Time
@docs onSecondChange, onMinuteChange, onHourChange, onDayChange, onMonthChange, onYearChange

# Animation
@docs onAnimationFinished

# Composition
@docs batch

-}

import Pebble.Ui exposing (AnimationId)

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


{-| Receive a message when a `drawVectorSequenceAt` or `drawBitmapSequenceAt`
instance finishes playing.

The runtime passes the `AnimationId` from the draw call. Use a fresh id for
each new play so replays and multiple on-screen instances stay independent.
-}
onAnimationFinished : (AnimationId -> msg) -> Sub msg
onAnimationFinished =
    Elm.Kernel.PebbleWatch.onAnimationFinished


{-| Combine multiple Pebble subscriptions into one.
-}
batch : List (Sub msg) -> Sub msg
batch =
    Elm.Kernel.PebbleWatch.batch
