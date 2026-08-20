module CompanionPreferences exposing (Settings, defaults, settings)

import Companion.Types exposing (ThemeColor(..))
import Pebble.Companion.Preferences as Preferences


type alias Settings =
    { motivationalText : String
    , watchSeconds : Float
    , quoteSeconds : Float
    , watchBackground : ThemeColor
    , watchForeground : ThemeColor
    , quoteBackground : ThemeColor
    , quoteText : ThemeColor
    }


defaults : Settings
defaults =
    { motivationalText = "Make today count."
    , watchSeconds = 5
    , quoteSeconds = 3
    , watchBackground = Cream
    , watchForeground = Black
    , quoteBackground = Cream
    , quoteText = Black
    }


settings : Preferences.Schema Settings
settings =
    Preferences.schema "Classic Motivate" Settings
        |> Preferences.section "Message"
            (\schema ->
                schema
                    |> Preferences.field "motivationalText"
                        (Preferences.text "Motivational text" "Make today count."
                            |> Preferences.sendToWatch "SetMotivationalText"
                        )
            )
        |> Preferences.section "Timing"
            (\schema ->
                schema
                    |> Preferences.field "watchSeconds"
                        (Preferences.slider "Seconds to show the watch"
                            { min = 3
                            , max = 30
                            , step = 1
                            , default = 5
                            }
                            |> Preferences.sendToWatch "SetWatchDisplaySeconds"
                        )
                    |> Preferences.field "quoteSeconds"
                        (Preferences.slider "Seconds to show the message"
                            { min = 3
                            , max = 10
                            , step = 1
                            , default = 3
                            }
                            |> Preferences.sendToWatch "SetQuoteDisplaySeconds"
                        )
            )
        |> Preferences.section "Watch face"
            (\schema ->
                schema
                    |> Preferences.field "watchBackground"
                        (Preferences.choice "Background" backgroundChoices
                            |> Preferences.sendToWatch "SetWatchBackground"
                        )
                    |> Preferences.field "watchForeground"
                        (Preferences.choice "Foreground" foregroundChoices
                            |> Preferences.sendToWatch "SetWatchForeground"
                        )
            )
        |> Preferences.section "Quote page"
            (\schema ->
                schema
                    |> Preferences.field "quoteBackground"
                        (Preferences.choice "Background" backgroundChoices
                            |> Preferences.sendToWatch "SetQuoteBackground"
                        )
                    |> Preferences.field "quoteText"
                        (Preferences.choice "Text" foregroundChoices
                            |> Preferences.sendToWatch "SetQuoteTextColor"
                        )
            )


backgroundChoices : List (Preferences.ChoiceOption ThemeColor)
backgroundChoices =
    [ Preferences.choiceOption Cream "cream" "Cream"
    , Preferences.choiceOption WatchBody "watch-body" "Watch body"
    , Preferences.choiceOption White "white" "White"
    , Preferences.choiceOption Black "black" "Black"
    , Preferences.choiceOption Brass "brass" "Brass"
    , Preferences.choiceOption Navy "navy" "Navy"
    , Preferences.choiceOption Slate "slate" "Slate"
    , Preferences.choiceOption Burgundy "burgundy" "Burgundy"
    , Preferences.choiceOption Magenta "magenta" "Magenta"
    ]


foregroundChoices : List (Preferences.ChoiceOption ThemeColor)
foregroundChoices =
    [ Preferences.choiceOption Black "black" "Black"
    , Preferences.choiceOption WatchBody "watch-body" "Watch body"
    , Preferences.choiceOption White "white" "White"
    , Preferences.choiceOption Cream "cream" "Cream"
    , Preferences.choiceOption Brass "brass" "Brass"
    , Preferences.choiceOption Navy "navy" "Navy"
    , Preferences.choiceOption Slate "slate" "Slate"
    , Preferences.choiceOption Burgundy "burgundy" "Burgundy"
    , Preferences.choiceOption Magenta "magenta" "Magenta"
    ]
