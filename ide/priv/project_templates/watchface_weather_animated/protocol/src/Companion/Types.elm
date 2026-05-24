module Companion.Types exposing (Location(..), PhoneToWatch(..), Temperature(..), WatchToPhone(..), WeatherCondition(..))

{-| Shared messages for the animated weather watchface.

Weather conditions match the companion weather demos. The phone companion fetches
Open-Meteo data and sends `ProvideCondition` updates to the watch.
-}


type Location
    = CurrentLocation
    | Berlin
    | Zurich
    | NewYork


type Temperature
    = Celsius Int
    | Fahrenheit Int


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


type WatchToPhone
    = RequestWeather Location


type PhoneToWatch
    = ProvideTemperature Temperature
    | ProvideCondition WeatherCondition
