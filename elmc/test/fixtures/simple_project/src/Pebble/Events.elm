module Pebble.Events exposing
    ( batch
    , onAccelTap
    , onButtonDown
    , onButtonLongDown
    , onButtonLongSelect
    , onButtonLongUp
    , onButtonSelect
    , onButtonUp
    , onHourChange
    , onMinuteChange
    , onTick
    )

import Elm.Kernel.PebbleWatch


onTick : (Int -> msg) -> Sub msg
onTick =
    Elm.Kernel.PebbleWatch.onTick


onHourChange : (Int -> msg) -> Sub msg
onHourChange =
    Elm.Kernel.PebbleWatch.onHourChange


onMinuteChange : (Int -> msg) -> Sub msg
onMinuteChange =
    Elm.Kernel.PebbleWatch.onMinuteChange


onButtonUp : msg -> Sub msg
onButtonUp =
    Elm.Kernel.PebbleWatch.onButtonUp


onButtonSelect : msg -> Sub msg
onButtonSelect =
    Elm.Kernel.PebbleWatch.onButtonSelect


onButtonDown : msg -> Sub msg
onButtonDown =
    Elm.Kernel.PebbleWatch.onButtonDown


onButtonLongUp : msg -> Sub msg
onButtonLongUp =
    Elm.Kernel.PebbleWatch.onButtonLongUp


onButtonLongSelect : msg -> Sub msg
onButtonLongSelect =
    Elm.Kernel.PebbleWatch.onButtonLongSelect


onButtonLongDown : msg -> Sub msg
onButtonLongDown =
    Elm.Kernel.PebbleWatch.onButtonLongDown


onAccelTap : msg -> Sub msg
onAccelTap =
    Elm.Kernel.PebbleWatch.onAccelTap


batch : List (Sub msg) -> Sub msg
batch =
    Elm.Kernel.PebbleWatch.batch
