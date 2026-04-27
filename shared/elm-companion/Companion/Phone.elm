module Companion.Phone exposing (decodeWatchToPhone, onWatchToPhone, sendPhoneToWatch)

{-| Companion-side API for receiving watch requests and sending responses. -}

import Companion.Internal as Internal
import Companion.Types exposing (PhoneToWatch, WatchToPhone)
import Json.Decode as Decode
import Pebble.Companion.AppMessage as AppMessage


{-| Decode a watch-originated request payload into a typed message. -}
decodeWatchToPhone : Decode.Value -> Result String WatchToPhone
decodeWatchToPhone =
    Internal.decodeWatchToPhonePayload


{-| Subscribe to watch-originated AppMessage payloads as typed protocol messages. -}
onWatchToPhone : (Result String WatchToPhone -> msg) -> Sub msg
onWatchToPhone toMsg =
    AppMessage.onMessage (decodeWatchToPhone >> toMsg)


{-| Encode and send a typed phone-to-watch response. -}
sendPhoneToWatch : PhoneToWatch -> Cmd msg
sendPhoneToWatch message =
    AppMessage.send (Internal.encodePhoneToWatch message)
