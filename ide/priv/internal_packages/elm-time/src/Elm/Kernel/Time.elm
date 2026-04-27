module Elm.Kernel.Time exposing (every, nowMillis, zoneOffsetMinutes)

import Platform.Sub exposing (Sub)


nowMillis : () -> Int
nowMillis _ =
    0


zoneOffsetMinutes : () -> Int
zoneOffsetMinutes _ =
    0


every : Float -> (a -> msg) -> Sub msg
every _ _ =
    Sub.none
