module Pebble.Vibes exposing (cancel, doublePulse, longPulse, shortPulse)

import Elm.Kernel.PebbleWatch

{-| Vibration motor controls.

@docs cancel, shortPulse, longPulse, doublePulse
-}


{-| Stop any in-progress vibration.
-}
cancel : Cmd msg
cancel =
    Elm.Kernel.PebbleWatch.vibesCancel


{-| Trigger a short vibration pulse.
-}
shortPulse : Cmd msg
shortPulse =
    Elm.Kernel.PebbleWatch.vibesShortPulse


{-| Trigger a long vibration pulse.
-}
longPulse : Cmd msg
longPulse =
    Elm.Kernel.PebbleWatch.vibesLongPulse


{-| Trigger a double vibration pulse.
-}
doublePulse : Cmd msg
doublePulse =
    Elm.Kernel.PebbleWatch.vibesDoublePulse
