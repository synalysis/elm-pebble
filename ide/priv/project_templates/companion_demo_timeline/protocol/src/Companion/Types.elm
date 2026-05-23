module Companion.Types exposing (PhoneToWatch(..), TimelinePinStatus(..), WatchToPhone(..))

{-| Demo protocol for timeline companion APIs.

Shows `Pebble.Companion.Timeline`.
-}


type WatchToPhone
    = RequestTimelineToken
    | InsertDemoPin


type TimelinePinStatus
    = PinOk
    | PinFailed


type PhoneToWatch
    = ProvideTimelineToken String
    | ProvideTimelineStatus TimelinePinStatus
