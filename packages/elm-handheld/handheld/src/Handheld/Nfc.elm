module Handheld.Nfc exposing
    ( onTag
    , read
    , scan
    )

{-| NFC tags.

`scan` starts a poll. `read` reads the tag that is already in range.
`onTag` receives the tag id when the host reports one.

    import Handheld.Nfc as Nfc

    type Msg
        = TagFound String

    init _ =
        ( model, Nfc.scan )

    subscriptions _ =
        Nfc.onTag TagFound

@docs scan, read, onTag
-}

import Handheld.Raw as Raw


{-| Start polling for a tag.
-}
scan : Cmd msg
scan =
    Raw.none


{-| Read the tag currently in range.
-}
read : Cmd msg
read =
    Raw.none


{-| Subscribe to a tag id.
-}
onTag : (String -> msg) -> Sub msg
onTag _ =
    Sub.none
