module Time exposing
    ( Month(..)
    , Posix
    , Weekday(..)
    , Zone
    , ZoneName(..)
    , customZone
    , every
    , getZoneName
    , here
    , millisToPosix
    , now
    , posixToMillis
    , toDay
    , toHour
    , toMillis
    , toMinute
    , toMonth
    , toSecond
    , toWeekday
    , toYear
    , utc
    )

{-| Library for working with time and time zones.

This is a built-in `elm/time` implementation for Pebble runtimes.

Use `now` for a one-shot timestamp or `every` for periodic ticks in a watch
application.

    update msg model =
        case msg of
            Tick time ->
                { model | seconds = Time.toSecond Time.utc time }

# Time values
@docs Posix, millisToPosix, posixToMillis

# Zones
@docs Zone, utc, here, customZone, getZoneName, ZoneName

# Calendar fields
@docs toYear, toMonth, toDay, toWeekday, toHour, toMinute, toSecond, toMillis

# Subscriptions and tasks
@docs now, every

# Calendar names
@docs Month, Weekday

-}

import Elm.Kernel.Time
import Platform.Sub exposing (Sub)
import Task exposing (Task)


{-| Milliseconds since the Unix epoch.
-}
type alias Posix =
    Int


{-| Get the current Pebble runtime time.
-}
now : Task x Posix
now =
    Task.succeed (millisToPosix (Elm.Kernel.Time.nowMillis ()))


{-| Convert a `Posix` value to milliseconds since the Unix epoch.
-}
posixToMillis : Posix -> Int
posixToMillis millis =
    millis


{-| Convert milliseconds since the Unix epoch to `Posix`.
-}
millisToPosix : Int -> Posix
millisToPosix =
    identity


{-| A time zone with a default offset and optional historical eras.
-}
type Zone
    = Zone Int (List Era)


type alias Era =
    { start : Int
    , offset : Int
    }


{-| Coordinated Universal Time.
-}
utc : Zone
utc =
    Zone 0 []


{-| Get the current Pebble local time zone.
-}
here : Task x Zone
here =
    Task.succeed (customZone (Elm.Kernel.Time.zoneOffsetMinutes ()) [])


{-| Extract the year in a given zone.
-}
toYear : Zone -> Posix -> Int
toYear zone time =
    (toCivil (toAdjustedMinutes zone time)).year


{-| Extract the month in a given zone.
-}
toMonth : Zone -> Posix -> Month
toMonth zone time =
    case (toCivil (toAdjustedMinutes zone time)).month of
        1 ->
            Jan

        2 ->
            Feb

        3 ->
            Mar

        4 ->
            Apr

        5 ->
            May

        6 ->
            Jun

        7 ->
            Jul

        8 ->
            Aug

        9 ->
            Sep

        10 ->
            Oct

        11 ->
            Nov

        _ ->
            Dec


{-| Extract the day of month in a given zone.
-}
toDay : Zone -> Posix -> Int
toDay zone time =
    (toCivil (toAdjustedMinutes zone time)).day


{-| Extract the weekday in a given zone.
-}
toWeekday : Zone -> Posix -> Weekday
toWeekday zone time =
    case modBy 7 (flooredDiv (toAdjustedMinutes zone time) (60 * 24)) of
        0 ->
            Thu

        1 ->
            Fri

        2 ->
            Sat

        3 ->
            Sun

        4 ->
            Mon

        5 ->
            Tue

        _ ->
            Wed


{-| Extract the hour of day in a given zone.
-}
toHour : Zone -> Posix -> Int
toHour zone time =
    modBy 24 (flooredDiv (toAdjustedMinutes zone time) 60)


{-| Extract the minute of hour in a given zone.
-}
toMinute : Zone -> Posix -> Int
toMinute zone time =
    modBy 60 (toAdjustedMinutes zone time)


{-| Extract the second of minute.
-}
toSecond : Zone -> Posix -> Int
toSecond _ time =
    modBy 60 (flooredDiv (posixToMillis time) 1000)


{-| Extract the millisecond of second.
-}
toMillis : Zone -> Posix -> Int
toMillis _ time =
    modBy 1000 (posixToMillis time)


toAdjustedMinutes : Zone -> Posix -> Int
toAdjustedMinutes (Zone defaultOffset eras) time =
    toAdjustedMinutesHelp defaultOffset (flooredDiv (posixToMillis time) 60000) eras


toAdjustedMinutesHelp : Int -> Int -> List Era -> Int
toAdjustedMinutesHelp defaultOffset posixMinutes eras =
    case eras of
        [] ->
            posixMinutes + defaultOffset

        era :: olderEras ->
            if era.start < posixMinutes then
                posixMinutes + era.offset

            else
                toAdjustedMinutesHelp defaultOffset posixMinutes olderEras


toCivil : Int -> { year : Int, month : Int, day : Int }
toCivil minutes =
    let
        rawDay =
            flooredDiv minutes (60 * 24) + 719468

        era =
            if rawDay >= 0 then
                rawDay // 146097

            else
                (rawDay - 146096) // 146097

        dayOfEra =
            rawDay - era * 146097

        yearOfEra =
            (dayOfEra - (dayOfEra // 1460) + (dayOfEra // 36524) - (dayOfEra // 146096)) // 365

        year =
            yearOfEra + era * 400

        dayOfYear =
            dayOfEra - (365 * yearOfEra + (yearOfEra // 4) - (yearOfEra // 100))

        mp =
            (5 * dayOfYear + 2) // 153

        month =
            mp
                + (if mp < 10 then
                    3

                   else
                    -9
                  )
    in
    { year =
        year
            + (if month <= 2 then
                1

               else
                0
              )
    , month = month
    , day = dayOfYear - ((153 * mp + 2) // 5) + 1
    }


flooredDiv : Int -> Int -> Int
flooredDiv numerator denominator =
    floor (toFloat numerator / toFloat denominator)


{-| Days of the week.
-}
type Weekday
    = Mon
    | Tue
    | Wed
    | Thu
    | Fri
    | Sat
    | Sun


{-| Months of the year.
-}
type Month
    = Jan
    | Feb
    | Mar
    | Apr
    | May
    | Jun
    | Jul
    | Aug
    | Sep
    | Oct
    | Nov
    | Dec


{-| Subscribe to periodic ticks.

    subscriptions model =
        Time.every 1000 Tick

-}
every : Float -> (Posix -> msg) -> Sub msg
every interval tagger =
    Elm.Kernel.Time.every interval (\_ -> tagger (millisToPosix (Elm.Kernel.Time.nowMillis ())))


{-| Build a custom time zone from an offset in minutes and optional eras.
-}
customZone : Int -> List { start : Int, offset : Int } -> Zone
customZone =
    Zone


{-| Get the runtime's current zone name or offset.
-}
getZoneName : Task x ZoneName
getZoneName =
    Task.succeed (Offset (Elm.Kernel.Time.zoneOffsetMinutes ()))


{-| A named time zone or a fixed offset in minutes.
-}
type ZoneName
    = Name String
    | Offset Int
