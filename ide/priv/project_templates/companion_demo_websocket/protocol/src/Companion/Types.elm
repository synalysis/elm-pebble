module Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..), WebSocketStatus(..))

{-| Demo protocol for WebSocket companion APIs.

Shows `Pebble.Companion.WebSocket`.
-}


type WatchToPhone
    = RequestWebSocketStatus
    | PingWebSocket


type WebSocketStatus
    = Closed
    | Open
    | Error


type PhoneToWatch
    = ProvideWebSocketStatus WebSocketStatus String
