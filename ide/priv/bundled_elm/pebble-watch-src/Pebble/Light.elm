module Pebble.Light exposing
    ( State(..)
    , disable
    , enable
    , interaction
    , onChange
    , resetColor
    , setColor
    , setRgb
    )

import Bitwise
import Elm.Kernel.PebbleWatch
import Pebble.Ui.Color as Color

{-| Backlight controls.

Use `interaction` for the default tap-to-light behavior, `enable` / `disable` to
force the backlight on or off, and `onChange` to observe transitions.
`setColor` and `setRgb` tint the backlight on watches with a color LED.
`resetColor` restores the user's default color.

    import Pebble.Light as Light

    type Msg
        = TurnOn
        | LightChanged Light.State

    update msg model =
        case msg of
            TurnOn ->
                ( model, Light.enable )

            LightChanged Light.On ->
                ( { model | backlight = True }, Cmd.none )

            LightChanged Light.Off ->
                ( { model | backlight = False }, Cmd.none )

    subscriptions _ =
        Light.onChange LightChanged

For a runnable example, use the **watch-demo-light** project template in the IDE.

@docs interaction, disable, enable, setColor, setRgb, resetColor, onChange, State
-}


{-| Whether the system backlight is currently on.
-}
type State
    = On
    | Off


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


{-| Set the backlight color from a Pebble palette color.

Watches without a color backlight ignore this command.
-}
setColor : Color.Color -> Cmd msg
setColor color =
    Elm.Kernel.PebbleWatch.backlightColor (Color.toInt color)


{-| Tint the backlight with 8-bit red, green, and blue channels (0..255).

The palette used by `setColor` only has two bits per channel. `setRgb` sends
the full channel values. Watches without a color backlight ignore this command.
-}
setRgb : Int -> Int -> Int -> Cmd msg
setRgb red green blue =
    let
        channel value =
            Basics.clamp 0 255 value
    in
    Elm.Kernel.PebbleWatch.backlightRgb888
        (Bitwise.or (Bitwise.shiftLeftBy 16 (channel red))
            (Bitwise.or (Bitwise.shiftLeftBy 8 (channel green)) (channel blue))
        )


{-| Restore the user's default backlight color.

Watches without a color backlight ignore this command.
-}
resetColor : Cmd msg
resetColor =
    Elm.Kernel.PebbleWatch.backlightResetColor


{-| Receive backlight on/off transitions from the Pebble runtime.
-}
onChange : (State -> msg) -> Sub msg
onChange =
    Elm.Kernel.PebbleWatch.onBacklightChange
