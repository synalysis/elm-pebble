module Pebble.Alarm exposing (next, toPosix)

{-| Query the next scheduled system alarm.

Use `next` to show an alarm indicator on a watchface. The callback receives
the UTC unix time in seconds, or `-1` when no enabled alarm is scheduled.

    import Pebble.Alarm as Alarm

    type Msg
        = GotNextAlarm Int

    init _ =
        ( model, Alarm.next GotNextAlarm )

    update msg model =
        case msg of
            GotNextAlarm utcSeconds ->
                ( { model | nextAlarm = Alarm.toPosix utcSeconds }, Cmd.none )

This API needs firmware that implements `alarm_service_peek_next`. On older
firmware the callback receives `-1`.

For a runnable example, use the **watch-demo-time** or **watchface-digital**
project template in the IDE.

# Commands
@docs next

# Helpers
@docs toPosix

-}

import Elm.Kernel.PebbleWatch
import Time


{-| Request the UTC unix seconds of the next enabled system alarm.

The callback receives `-1` when no enabled alarm is scheduled.
-}
next : (Int -> msg) -> Cmd msg
next =
    Elm.Kernel.PebbleWatch.alarmNext


{-| Convert a `next` result to `Time.Posix`.

`Nothing` when the value is negative (no alarm scheduled).
-}
toPosix : Int -> Maybe Time.Posix
toPosix utcSeconds =
    if utcSeconds < 0 then
        Nothing

    else
        Just (Time.millisToPosix (utcSeconds * 1000))
