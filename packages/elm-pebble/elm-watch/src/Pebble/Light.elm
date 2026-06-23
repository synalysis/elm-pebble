module Pebble.Light exposing (disable, enable, interaction, onChange, State(..))

import Elm.Kernel.PebbleWatch

{-| Backlight controls.

Use `interaction` for the default tap-to-light behavior, `enable` / `disable` to
force the backlight on or off, and `onChange` to observe transitions.

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

@docs interaction, disable, enable, onChange, State
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


{-| Receive backlight on/off transitions from the Pebble runtime.
-}
onChange : (State -> msg) -> Sub msg
onChange =
    Elm.Kernel.PebbleWatch.onBacklightChange
