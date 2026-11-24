module Handheld.Radio exposing (get)

{-| HTTP over the radio module.

MeowKit uses Wi-Fi. Flipper uses the network stack it has.

    import Handheld.Radio as Radio

    init _ =
        ( model, Radio.get "http://example.com" )

@docs get
-}

import Handheld.Raw as Raw


{-| Send an HTTP GET.
-}
get : String -> Cmd msg
get _ =
    Raw.none
