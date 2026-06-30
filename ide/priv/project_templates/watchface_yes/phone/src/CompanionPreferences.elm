module CompanionPreferences exposing (CornerUpdateInterval(..), Settings, intervalSeconds, preferencesDefaults, settings)

import Pebble.Companion.Preferences as Preferences


type alias Settings =
    { cornerUpdateInterval : CornerUpdateInterval
    }


type CornerUpdateInterval
    = FiveSeconds
    | TenSeconds
    | ThirtySeconds
    | SixtySeconds


preferencesDefaults : Settings
preferencesDefaults =
    { cornerUpdateInterval = FiveSeconds }


intervalSeconds : CornerUpdateInterval -> Int
intervalSeconds interval =
    case interval of
        FiveSeconds ->
            5

        TenSeconds ->
            10

        ThirtySeconds ->
            30

        SixtySeconds ->
            60


settings : Preferences.Schema Settings
settings =
    Preferences.schema "YES Watchface" Settings
        |> Preferences.section "Corners"
            (\schema ->
                schema
                    |> Preferences.field "cornerUpdateInterval"
                        (Preferences.choice "Corner update interval"
                            [ Preferences.choiceOption FiveSeconds "5" "5 seconds"
                            , Preferences.choiceOption TenSeconds "10" "10 seconds"
                            , Preferences.choiceOption ThirtySeconds "30" "30 seconds"
                            , Preferences.choiceOption SixtySeconds "60" "60 seconds"
                            ]
                            |> Preferences.sendToWatch "SetCornerUpdateInterval"
                        )
            )
