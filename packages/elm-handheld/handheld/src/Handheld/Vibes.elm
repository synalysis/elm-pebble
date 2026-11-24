module Handheld.Vibes exposing
    ( cancel
    , doublePulse
    , longPulse
    , shortPulse
    )

{-| The vibration motor.

    import Handheld.Vibes as Vibes

    onOk =
        Vibes.shortPulse

@docs shortPulse, longPulse, doublePulse, cancel
-}

import Handheld.Raw as Raw


{-| A short pulse.
-}
shortPulse : Cmd msg
shortPulse =
    Raw.none


{-| A long pulse.
-}
longPulse : Cmd msg
longPulse =
    Raw.none


{-| Two short pulses.
-}
doublePulse : Cmd msg
doublePulse =
    Raw.none


{-| Stop a pulse that is still playing.
-}
cancel : Cmd msg
cancel =
    Raw.none
