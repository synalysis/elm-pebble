module Companion.Types exposing (PhoneToWatch(..), Theme(..), Units(..), WatchToPhone(..))

{-| Demo protocol for storage and preference companion APIs.

Shows `Pebble.Companion.Storage` and `PreferenceStore`.
-}


type WatchToPhone
    = RequestStoredValues
    | CycleTheme


type Theme
    = Dark
    | Light


type Units
    = Metric
    | Imperial


type PhoneToWatch
    = ProvideTheme Theme Units
