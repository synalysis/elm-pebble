module Pebble.Time exposing
    ( CurrentDateTime
    , DayOfWeek(..)
    , clockStyle24h
    , currentDateTime
    , currentTimeString
    , timezone
    , timezoneIsSet
    )

{-| Commands for reading watch time and timezone information.

Request structured time in `init` or on a timer, and combine with
`Pebble.Cmd.timerAfter` for periodic refresh.

    import Pebble.Time as Time

    type Msg
        = GotDateTime Time.CurrentDateTime
        | GotTimezone String

    init _ =
        ( model
        , Cmd.batch
            [ Time.currentDateTime GotDateTime
            , Time.timezone GotTimezone
            ]
        )

For scheduling refreshes, pair with `Pebble.Cmd.timerAfter` from `Pebble.Cmd`.
See the **watch-demo-time** project template in the IDE.

# Time and timezone
@docs DayOfWeek, CurrentDateTime, currentDateTime, currentTimeString, clockStyle24h, timezoneIsSet, timezone

-}


import Elm.Kernel.PebbleWatch


{-| Structured local time/date information from the watch runtime.
-}
type DayOfWeek
    = Monday
    | Tuesday
    | Wednesday
    | Thursday
    | Friday
    | Saturday
    | Sunday


{-| Structured local time/date information from the watch runtime.
-}
type alias CurrentDateTime =
    { year : Int
    , month : Int
    , day : Int
    , dayOfWeek : DayOfWeek
    , hour : Int
    , minute : Int
    , second : Int
    , utcOffsetMinutes : Int
    }


{-| Request the current local date/time with UTC offset in minutes.
-}
currentDateTime : (CurrentDateTime -> msg) -> Cmd msg
currentDateTime =
    Elm.Kernel.PebbleWatch.getCurrentDateTime


{-| Request the current local time string from the watch runtime.
-}
currentTimeString : (String -> msg) -> Cmd msg
currentTimeString =
    Elm.Kernel.PebbleWatch.getCurrentTimeString


{-| Request whether the user is using 24-hour time.
-}
clockStyle24h : (Bool -> msg) -> Cmd msg
clockStyle24h =
    Elm.Kernel.PebbleWatch.getClockStyle24h


{-| Request whether timezone data is currently available.
-}
timezoneIsSet : (Bool -> msg) -> Cmd msg
timezoneIsSet =
    Elm.Kernel.PebbleWatch.getTimezoneIsSet


{-| Request the current timezone identifier string.
-}
timezone : (String -> msg) -> Cmd msg
timezone =
    Elm.Kernel.PebbleWatch.getTimezone
