module Pebble.Log exposing (errorCode, infoCode, warnCode)

import Elm.Kernel.PebbleWatch

{-| Runtime logging commands.

This app-focused wave exposes integer code logging for deterministic C-side
logging output.

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
