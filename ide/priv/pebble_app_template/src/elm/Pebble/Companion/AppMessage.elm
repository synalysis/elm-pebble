port module Pebble.Companion.AppMessage exposing (onMessage, send)

{-| Phone-side Pebble appmessage bridge.

This hides the raw JavaScript ports from companion app code. The generated PKJS
boot code wires these ports to `Pebble.addEventListener("appmessage", ...)` and
`Pebble.sendAppMessage(...)`.
-}

import Json.Decode as Decode
import Json.Encode as Encode


port incoming : (Decode.Value -> msg) -> Sub msg


port outgoing : Encode.Value -> Cmd msg


onMessage : (Decode.Value -> msg) -> Sub msg
onMessage =
    incoming


send : Encode.Value -> Cmd msg
send =
    outgoing
