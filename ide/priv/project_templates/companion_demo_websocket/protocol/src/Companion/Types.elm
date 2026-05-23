module Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))

{-| Demo protocol for WebSocket companion APIs.

Shows `Pebble.Companion.WebSocket`.
-}


type WatchToPhone
    = RequestWebSocketStatus
    | PingWebSocket


type PhoneToWatch
    = ProvideWebSocketStatus Int String
