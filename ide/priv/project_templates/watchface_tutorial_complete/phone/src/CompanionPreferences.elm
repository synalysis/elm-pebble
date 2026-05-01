module CompanionPreferences exposing (Settings, settings)

import Companion.Types exposing (TutorialColor(..))
import Pebble.Companion.Preferences as Preferences


type alias Settings =
    { backgroundColor : TutorialColor
    , textColor : TutorialColor
    , showDate : Bool
    }


settings : Preferences.Schema Settings
settings =
    Preferences.schema "Tutorial Watchface" Settings
        |> Preferences.section "Colors"
            (\schema ->
                schema
                    |> Preferences.field "backgroundColor"
                        (Preferences.choice "Background"
                            [ Preferences.choiceOption Black "black" "Black"
                            , Preferences.choiceOption White "white" "White"
                            , Preferences.choiceOption Green "green" "Green"
                            , Preferences.choiceOption Blue "blue" "Blue"
                            , Preferences.choiceOption Yellow "yellow" "Yellow"
                            ]
                            |> Preferences.sendToWatch "SetBackgroundColor"
                        )
                    |> Preferences.field "textColor"
                        (Preferences.choice "Text"
                            [ Preferences.choiceOption White "white" "White"
                            , Preferences.choiceOption Black "black" "Black"
                            , Preferences.choiceOption Green "green" "Green"
                            , Preferences.choiceOption Blue "blue" "Blue"
                            , Preferences.choiceOption Yellow "yellow" "Yellow"
                            ]
                            |> Preferences.sendToWatch "SetTextColor"
                        )
            )
        |> Preferences.section "Display"
            (\schema ->
                schema
                    |> Preferences.field "showDate"
                        (Preferences.toggle "Show date" True
                            |> Preferences.sendToWatch "SetShowDate"
                        )
            )
