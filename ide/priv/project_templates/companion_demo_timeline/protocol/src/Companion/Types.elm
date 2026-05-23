module Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))

{-| Demo protocol for timeline companion APIs.

Shows `Pebble.Companion.Timeline`.
-}


type WatchToPhone
    = RequestTimelineToken
    | InsertDemoPin


type PhoneToWatch
    = ProvideTimelineToken String
    | ProvideTimelineStatus Int
