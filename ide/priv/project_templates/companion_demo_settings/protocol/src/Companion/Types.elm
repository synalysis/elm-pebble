module Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))

{-| Demo protocol for configuration and lifecycle companion APIs.

Shows `Pebble.Companion.Configuration` and `Lifecycle`.
-}


type WatchToPhone
    = OpenSettings


type PhoneToWatch
    = SettingsReady
    | SettingsClosed Bool
