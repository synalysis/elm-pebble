module Pebble.DataLog exposing (Tag, logBytes, logInt32)

{-| Log analytics bytes to the Pebble data logging service.

@docs Tag, logBytes, logInt32

-}

import Elm.Kernel.PebbleWatch


{-| A data logging session tag (uint32 on device).
-}
type Tag
    = Tag Int


{-| Log a list of byte values (0–255) under the given tag.
-}
logBytes : Tag -> List Int -> Cmd msg
logBytes (Tag tag) bytes =
    Elm.Kernel.PebbleWatch.dataLogBytes tag bytes


{-| Log a single 32-bit integer under the given tag.
-}
logInt32 : Tag -> Int -> Cmd msg
logInt32 (Tag tag) value =
    Elm.Kernel.PebbleWatch.dataLogInt32 tag value
