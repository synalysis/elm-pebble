module Pebble.Events exposing (batch, onHourChange, onMinuteChange, onSecondChange, onTick)


batch : List (Sub msg) -> Sub msg
batch =
    Sub.batch


onSecondChange : (Int -> msg) -> Sub msg
onSecondChange _ =
    Sub.none


onTick : (Int -> msg) -> Sub msg
onTick =
    onSecondChange


onHourChange : (Int -> msg) -> Sub msg
onHourChange _ =
    Sub.none


onMinuteChange : (Int -> msg) -> Sub msg
onMinuteChange _ =
    Sub.none
