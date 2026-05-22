module Pebble.Wakeup exposing (cancel, scheduleAfterSeconds)

import Elm.Kernel.PebbleWatch

{-| Wakeup scheduling commands.

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
