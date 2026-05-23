module Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))

{-| Demo protocol for storage and preference companion APIs.

Shows `Pebble.Companion.Storage` and `PreferenceStore`.
-}


type WatchToPhone
    = RequestStoredValues
    | CycleTheme


type PhoneToWatch
    = ProvideTheme String String
