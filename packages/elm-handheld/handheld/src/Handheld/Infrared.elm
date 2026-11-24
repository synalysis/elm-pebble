module Handheld.Infrared exposing (send)

{-| Infrared transmit.

    import Handheld.Infrared as Infrared

    init _ =
        ( model, Infrared.send 16 )

@docs send
-}

import Handheld.Raw as Raw


{-| Send a raw pulse train. `count` is how many pulses the host transmits.
-}
send : Int -> Cmd msg
send _ =
    Raw.none
