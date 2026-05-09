module Pebble.Button exposing
    ( Button(..)
    , Event(..)
    , on
    , onLongPress
    , onPress
    , onRelease
    )

{-| Button subscriptions for Pebble watches.

# Types
@docs Button, Event

# Subscriptions
@docs on, onPress, onRelease, onLongPress

-}

import Elm.Kernel.PebbleWatch


{-| Physical buttons available on a Pebble watch.
-}
type Button
    = Back
    | Up
    | Select
    | Down


{-| Button event edge to subscribe to.
-}
type Event
    = Pressed
    | Released
    | LongPressed


{-| Subscribe to a specific button event.
-}
on : Button -> Event -> msg -> Sub msg
on button event msg =
    Elm.Kernel.PebbleWatch.onButtonRaw (buttonToInt button) (eventToInt event) msg


{-| Subscribe to a button press.
-}
onPress : Button -> msg -> Sub msg
onPress button msg =
    on button Pressed msg


{-| Subscribe to a button release.
-}
onRelease : Button -> msg -> Sub msg
onRelease button msg =
    on button Released msg


{-| Subscribe to a long button press.
-}
onLongPress : Button -> msg -> Sub msg
onLongPress button msg =
    on button LongPressed msg


buttonToInt button =
    case button of
        Back ->
            0

        Up ->
            1

        Select ->
            2

        Down ->
            3


eventToInt event =
    case event of
        Pressed ->
            1

        Released ->
            2

        LongPressed ->
            3
