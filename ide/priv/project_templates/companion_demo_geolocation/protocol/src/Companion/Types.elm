module Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))

{-| Demo protocol for geolocation companion APIs.

Shows `Pebble.Companion.Geolocation`.
-}


type WatchToPhone
    = RequestPosition


type PhoneToWatch
    = ProvidePosition Int Int Int
