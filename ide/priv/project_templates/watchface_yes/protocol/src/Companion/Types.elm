module Companion.Types exposing (AltitudeUnit(..), InternetMode(..), PhoneToWatch(..), SunMode(..), TemperatureUnit(..), TideKind(..), WatchToPhone(..), WeatherCondition(..), WindUnit(..))

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


type TemperatureUnit
    = Celsius
    | Fahrenheit


type WindUnit
    = MetersPerSecond
    | MilesPerHour


type TideKind
    = HighTide
    | LowTide


type AltitudeUnit
    = Meters
    | Feet


type InternetMode
    = InternetEnabled
    | InternetDisabled


type WatchToPhone
    = RequestUpdate


type PhoneToWatch
    = ProvideLocation Int Int Int
    | ProvideSun Int Int SunMode
    | ProvideMoon Int Int Int
    | ProvideMoonPhase Int
    | ProvideWeather Int WeatherCondition Int Int Int TemperatureUnit
    | ProvideWind Int Int WindUnit
    | ProvideTide Int Int Int TideKind
    | ClearTide
    | ProvideAltitude Int AltitudeUnit
    | SetUseInternet InternetMode
    | SetUnits TemperatureUnit WindUnit
