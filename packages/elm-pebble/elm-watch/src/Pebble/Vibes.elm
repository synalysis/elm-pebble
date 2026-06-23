module Pebble.Vibes exposing (cancel, doublePulse, longPulse, pattern, shortPulse)

import Elm.Kernel.PebbleWatch

{-| Vibration motor controls.

Use built-in pulses for simple feedback, or `pattern` for custom rhythms.
Each pattern value is a segment duration in milliseconds, alternating ON/OFF.

    import Pebble.Vibes as Vibes

    sos : Cmd msg
    sos =
        Vibes.pattern [ 100, 100, 100, 100, 100, 300, 300, 300, 100, 100, 100 ]

    onTap : Cmd msg
    onTap =
        Vibes.shortPulse

For a runnable example, use the **watch-demo-vibes** project template in the IDE.

@docs cancel, shortPulse, longPulse, doublePulse, pattern
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


{-| Play a custom vibration pattern.

Each value is a segment duration in milliseconds. Segments alternate ON/OFF starting with ON.
-}
pattern : List Int -> Cmd msg
pattern segments =
    Elm.Kernel.PebbleWatch.vibesCustomPattern segments
