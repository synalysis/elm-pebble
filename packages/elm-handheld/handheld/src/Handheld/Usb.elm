module Handheld.Usb exposing
    ( Key
    , code
    , enter
    , escape
    , space
    , tab
    , tap
    )

{-| USB keyboard taps.

Check `Device.ready Usb` first. Flipper Zero has no USB HID module, so the
command does nothing there.

    import Handheld.Usb as Usb

    send =
        Usb.tap Usb.enter

@docs Key, tap, code, enter, escape, tab, space
-}

import Handheld.Raw as Raw


{-| A USB HID key.
-}
type Key
    = Key Int


{-| Tap a key, as if it was pressed and released.
-}
tap : Key -> Cmd msg
tap _ =
    Raw.none


{-| A key from its HID usage code.
-}
code : Int -> Key
code =
    Key


{-| Enter.
-}
enter : Key
enter =
    code 40


{-| Escape.
-}
escape : Key
escape =
    code 41


{-| Tab.
-}
tab : Key
tab =
    code 43


{-| Space.
-}
space : Key
space =
    code 44
