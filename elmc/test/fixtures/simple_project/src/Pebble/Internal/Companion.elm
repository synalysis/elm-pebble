module Pebble.Internal.Companion exposing (companionSend)

import Pebble.Cmd


companionSend : Int -> Int -> Cmd msg
companionSend =
    Pebble.Cmd.companionSend
