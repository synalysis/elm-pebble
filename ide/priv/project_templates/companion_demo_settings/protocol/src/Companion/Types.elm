module Companion.Types exposing (ConfigurationOutcome(..), PhoneToWatch(..), WatchToPhone(..))

{-| Demo protocol for configuration and lifecycle companion APIs.

Shows `Pebble.Companion.Configuration` and `Lifecycle`.
-}


type WatchToPhone
    = OpenSettings


type ConfigurationOutcome
    = Saved
    | Dismissed


type PhoneToWatch
    = SettingsReady
    | SettingsClosed ConfigurationOutcome
