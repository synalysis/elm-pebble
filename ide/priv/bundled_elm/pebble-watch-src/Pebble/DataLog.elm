module Pebble.DataLog exposing (Tag, tag, logBytes, logInt32)

{-| Log analytics bytes to the Pebble data logging service.

Each log session is identified by a numeric tag (uint32 on device). Create tags
with `tag` and pass them to `logBytes` or `logInt32`.

@docs Tag, tag, logBytes, logInt32

-}

import Elm.Kernel.PebbleWatch


{-| A data logging session tag (uint32 on device).
-}
type Tag
    = Tag Int


{-| Create a data logging tag from a uint32 session id.
-}
tag : Int -> Tag
tag =
    Tag


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
