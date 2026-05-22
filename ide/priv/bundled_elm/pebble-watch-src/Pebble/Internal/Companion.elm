module Pebble.Internal.Companion exposing (companionSend)

import Elm.Kernel.PebbleWatch


companionSend : Int -> Int -> Cmd msg
companionSend =
    Elm.Kernel.PebbleWatch.companionSend
