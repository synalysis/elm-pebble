module Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))

{-| Demo protocol for weather and environment companion APIs.

Shows `Pebble.Companion.Weather` and `Environment`.
-}


type WatchToPhone
    = RequestWeatherEnv


type PhoneToWatch
    = ProvideWeather Int Int
    | ProvideEnvironment Int Int Int
