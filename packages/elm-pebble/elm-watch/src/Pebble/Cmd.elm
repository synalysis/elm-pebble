module Pebble.Cmd exposing
    ( CurrentDateTime
    , getCurrentDateTime
    , none
    , timerAfter
    )

{-| Core watch commands.

Use this module for generic scheduling. Hardware controls live in
`Pebble.Hardware`, watch metadata requests live in `Pebble.WatchInfo`, and
key-value persistence helpers live in `Pebble.Storage`.

    type Msg
        = WakeUp

    scheduleWakeUp : Cmd Msg
    scheduleWakeUp =
        timerAfter 1000

# Scheduling
@docs none, timerAfter

# Time
@docs CurrentDateTime, getCurrentDateTime

-}


import Elm.Kernel.PebbleWatch
import Time exposing (Weekday)


{-| A command that does nothing.
-}
none : Cmd msg
none =
    Elm.Kernel.PebbleWatch.none


{-| Structured local time/date information from the watch runtime.
-}
type alias CurrentDateTime =
    { year : Int
    , month : Int
    , day : Int
    , dayOfWeek : Weekday
    , hour : Int
    , minute : Int
    , second : Int
    , utcOffsetMinutes : Int
    }


{-| Run a command after `ms` milliseconds.
-}
timerAfter : Int -> Cmd msg
timerAfter =
    Elm.Kernel.PebbleWatch.timerAfter


{-| Request the current local date/time with UTC offset in minutes.
-}
getCurrentDateTime : (CurrentDateTime -> msg) -> Cmd msg
getCurrentDateTime =
    Elm.Kernel.PebbleWatch.getCurrentDateTime


