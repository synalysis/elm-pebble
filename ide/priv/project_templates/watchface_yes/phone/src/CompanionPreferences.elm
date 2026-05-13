module CompanionPreferences exposing (Settings, preferencesDefaults, settings)

import Companion.Types exposing (InternetMode(..), TemperatureUnit(..), WindUnit(..))
import Pebble.Companion.Preferences as Preferences


type alias Settings =
    { homeLatitude : Float
    , homeLongitude : Float
    , homeTzOffsetMinutes : Float
    , internetMode : InternetMode
    , showTide : Bool
    , temperatureUnit : TemperatureUnit
    , windUnit : WindUnit
    }


preferencesDefaults : Settings
preferencesDefaults =
    { homeLatitude = 52.52
    , homeLongitude = 13.41
    , homeTzOffsetMinutes = 60
    , internetMode = InternetEnabled
    , showTide = True
    , temperatureUnit = Celsius
    , windUnit = MetersPerSecond
    }


settings : Preferences.Schema Settings
settings =
    Preferences.schema "YES Watchface" Settings
        |> Preferences.section "Home"
            (\schema ->
                schema
                    |> Preferences.field "homeLatitude"
                        (Preferences.number "Latitude" 52.52)
                    |> Preferences.field "homeLongitude"
                        (Preferences.number "Longitude" 13.41)
                    |> Preferences.field "homeTzOffsetMinutes"
                        (Preferences.number "UTC offset minutes" 60)
            )
        |> Preferences.section "Data"
            (\schema ->
                schema
                    |> Preferences.field "internetMode"
                        (Preferences.choice "Internet data"
                            [ Preferences.choiceOption InternetEnabled "enabled" "Enabled"
                            , Preferences.choiceOption InternetDisabled "disabled" "Disabled"
                            ]
                            |> Preferences.sendToWatch "SetUseInternet"
                        )
                    |> Preferences.field "showTide"
                        (Preferences.toggle "Show tide complication" True)
            )
        |> Preferences.section "Units"
            (\schema ->
                schema
                    |> Preferences.field "temperatureUnit"
                        (Preferences.choice "Temperature"
                            [ Preferences.choiceOption Celsius "celsius" "Celsius"
                            , Preferences.choiceOption Fahrenheit "fahrenheit" "Fahrenheit"
                            ]
                        )
                    |> Preferences.field "windUnit"
                        (Preferences.choice "Wind and altitude"
                            [ Preferences.choiceOption MetersPerSecond "metric" "m/s and meters"
                            , Preferences.choiceOption MilesPerHour "imperial" "mph and feet"
                            ]
                        )
            )
