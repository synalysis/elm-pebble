module Pebble.Light exposing (disable, enable, interaction)

import Elm.Kernel.PebbleWatch

{-| Backlight controls.

@docs interaction, disable, enable
-}


{-| Trigger the default interaction backlight behavior.
-}
interaction : Cmd msg
interaction =
    Elm.Kernel.PebbleWatch.backlight Nothing


{-| Force backlight off.
-}
disable : Cmd msg
disable =
    Elm.Kernel.PebbleWatch.backlight (Just False)


{-| Force backlight on.
-}
enable : Cmd msg
enable =
    Elm.Kernel.PebbleWatch.backlight (Just True)
