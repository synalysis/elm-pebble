module Companion.Types exposing (Altitude(..), PhoneToWatch(..), SunMode(..), Temperature(..), TideKind(..), WatchToPhone(..), WeatherCondition(..), WindDirection(..), WindSpeed(..))

{-| Shared YES watchface messages.
-}


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


type SunMode
    = SunCycle
    | PolarDay
    | PolarNight


{-| Temperature in tenths of a degree in the tagged unit.
-}
type Temperature
    = Celsius Int
    | Fahrenheit Int


{-| Wind speed in the tagged unit.
-}
type WindSpeed
    = MetersPerSecond Int
    | MilesPerHour Int


type WindDirection
    = North
    | NorthEast
    | East
    | SouthEast
    | South
    | SouthWest
    | West
    | NorthWest


type TideKind
    = HighTide
    | LowTide


type Altitude
    = Meters Int
    | Feet Int


type WatchToPhone
    = RequestUpdate


type PhoneToWatch
    = ProvideTimezone Int
    | ProvideSun Int Int SunMode
    | ProvideMoon Int Int Int
    | ProvideMoonPhase Int
    | ProvideWeather Temperature WeatherCondition Int Int Int
    | ProvideWind WindDirection WindSpeed
    | ProvideTide Int Int Int TideKind
    | ClearTide
    | ProvideAltitude Altitude
    | SetCornerUpdateInterval Int
