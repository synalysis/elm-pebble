module Pebble.Log exposing (errorCode, infoCode, warnCode)

import Elm.Kernel.PebbleWatch

{-| Runtime logging commands.

Emit integer codes from your update loop; the C runtime prints them to the
device log (visible in debug builds and the IDE debugger).

    import Pebble.Log as Log

    reportFailure : Cmd msg
    reportFailure =
        Log.errorCode 3001

For a runnable example, use the **watch-demo-log** project template in the IDE.

@docs infoCode, warnCode, errorCode
-}


{-| Emit an info-level log event.
-}
infoCode : Int -> Cmd msg
infoCode =
    Elm.Kernel.PebbleWatch.logInfoCode


{-| Emit a warning-level log event.
-}
warnCode : Int -> Cmd msg
warnCode =
    Elm.Kernel.PebbleWatch.logWarnCode


{-| Emit an error-level log event.
-}
errorCode : Int -> Cmd msg
errorCode =
    Elm.Kernel.PebbleWatch.logErrorCode
