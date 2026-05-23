module Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..), WeatherCondition(..))

{-| Demo protocol for weather and environment companion APIs.

Shows `Pebble.Companion.Weather` and `Environment`.
-}


type WatchToPhone
    = RequestWeatherEnv


type WeatherCondition
    = Clear
    | Cloudy
    | Fog
    | Drizzle
    | Rain
    | Snow
    | Showers
    | Storm
    | UnknownWeather


type PhoneToWatch
    = ProvideWeather Int WeatherCondition
    | ProvideEnvironment Int Int Int
