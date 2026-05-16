module Pebble.Button exposing (Button(..), Event(..), on, onLongPress, onPress, onRelease)


type Button
    = Back
    | Up
    | Select
    | Down


type Event
    = Pressed
    | Released
    | LongPressed


on : Button -> Event -> msg -> Sub msg
on _ _ _ =
    Sub.none


onPress : Button -> msg -> Sub msg
onPress button msg =
    on button Pressed msg


onRelease : Button -> msg -> Sub msg
onRelease button msg =
    on button Released msg


onLongPress : Button -> msg -> Sub msg
onLongPress button msg =
    on button LongPressed msg
