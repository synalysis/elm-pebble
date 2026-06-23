module Pebble.Wakeup exposing (cancel, scheduleAfterSeconds)

import Elm.Kernel.PebbleWatch

{-| Wakeup scheduling commands.

Schedule the app to relaunch after a delay. When the wakeup fires, `init` receives
`LaunchWakeup` in `Platform.LaunchContext.reason`.

    import Pebble.Wakeup as Wakeup

    type Msg
        = ScheduleReminder

    update msg model =
        case msg of
            ScheduleReminder ->
                ( model, Wakeup.scheduleAfterSeconds 60 )

Pass the wakeup id returned by the native runtime to `cancel` if you need to
revoke a pending wakeup before it fires.

For a runnable example, use the **watch-demo-wakeup** project template in the IDE.

@docs scheduleAfterSeconds, cancel
-}


{-| Schedule the app to be woken up after `seconds`.
-}
scheduleAfterSeconds : Int -> Cmd msg
scheduleAfterSeconds =
    Elm.Kernel.PebbleWatch.wakeupScheduleAfterSeconds


{-| Cancel a scheduled wakeup by id.
-}
cancel : Int -> Cmd msg
cancel =
    Elm.Kernel.PebbleWatch.wakeupCancel
