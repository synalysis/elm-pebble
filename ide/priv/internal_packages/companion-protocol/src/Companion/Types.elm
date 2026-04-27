module Companion.Types exposing (Location(..), PhoneToWatch(..), Temperature(..), TutorialColor(..), WatchToPhone(..), WeatherCondition(..))

{-| Shared message types exchanged between watch and companion.

These small examples are used by the starter companion protocol and are useful
when experimenting with typed watch-to-phone messages.

    RequestWeather Berlin

# Shared protocol
@docs Location, Temperature, WeatherCondition, TutorialColor, WatchToPhone, PhoneToWatch

-}


{-| Supported weather locations for the sample weather request.
-}
type Location
    = CurrentLocation
    | Berlin
    | Zurich
    | NewYork


{-| Weather value with its display unit.
-}
type Temperature
    = Celsius Int
    | Fahrenheit Int


{-| Generalized weather condition sent by the companion.
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


{-| Tutorial color choices sent by the phone configuration flow.
-}
type TutorialColor
    = Black
    | White
    | Green
    | Blue
    | Yellow


{-| Requests sent from the watch to the phone companion.
-}
type WatchToPhone
    = RequestWeather Location


{-| Responses sent from the phone companion back to the watch.
-}
type PhoneToWatch
    = ProvideTemperature Temperature
    | ProvideCondition WeatherCondition
    | SetBackgroundColor TutorialColor
    | SetTextColor TutorialColor
    | SetShowDate Bool
