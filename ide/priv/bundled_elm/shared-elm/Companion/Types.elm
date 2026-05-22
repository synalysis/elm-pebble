module Companion.Types exposing (Location(..), PhoneToWatch(..), Temperature(..), TutorialColor(..), WatchToPhone(..), WeatherCondition(..))

{-| Shared message types exchanged between watch and companion.
-}


{-| Supported weather locations. -}
type Location
    = CurrentLocation
    | Berlin
    | Zurich
    | NewYork


{-| Weather value with its display unit. -}
type Temperature
    = Celsius Int
    | Fahrenheit Int


{-| Generalized weather condition sent by the companion. -}
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


{-| Tutorial color choices. -}
type TutorialColor
    = Black
    | White
    | Green
    | Blue
    | Yellow


{-| Requests sent from watch to phone. -}
type WatchToPhone
    = RequestWeather Location


{-| Responses sent from phone to watch. -}
type PhoneToWatch
    = ProvideTemperature Temperature
    | ProvideCondition WeatherCondition
    | SetBackgroundColor TutorialColor
    | SetTextColor TutorialColor
    | SetShowDate Bool
