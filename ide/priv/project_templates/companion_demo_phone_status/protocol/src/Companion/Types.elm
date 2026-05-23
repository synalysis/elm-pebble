module Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))

{-| Demo protocol for phone status companion APIs.

Shows `Pebble.Companion.Battery`, `Locale`, `Connectivity`, and `Notifications`.
-}


type WatchToPhone
    = RequestPhoneStatus


type PhoneToWatch
    = ProvideBattery Int Bool
    | ProvideLocale String
    | ProvideConnectivity Bool
    | ProvideNotifications Bool Bool
