module Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..), WebSocketStatus(..))

{-| Demo protocol for WebSocket companion APIs.

Shows `mbr/elm-wss` via application-owned `wsCmd` / `wsMsg` ports.
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
