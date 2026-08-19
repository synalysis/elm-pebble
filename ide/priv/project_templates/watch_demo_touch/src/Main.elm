module Main exposing (main)

import Json.Decode as Decode
import Pebble.Button as Button
import Pebble.Events as Events
import Pebble.Platform as Platform
import Pebble.Touch as Touch
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources


type alias Model =
    { supported : Maybe Bool
    , lastGesture : String
    , refreshes : Int
    }


type Msg
    = SelectPressed
    | GotSupported Bool
    | Tapped Touch.Point
    | Panned Touch.PanEvent
    | Swiped Touch.SwipeEvent


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init _ =
    ( { supported = Nothing
      , lastGesture = "Waiting"
      , refreshes = 0
      }
    , Touch.supported GotSupported
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SelectPressed ->
            ( { model | refreshes = model.refreshes + 1 }, Touch.supported GotSupported )

        GotSupported value ->
            ( { model | supported = Just value }, Cmd.none )

        Tapped point ->
            ( { model | lastGesture = "Tap " ++ String.fromInt point.x ++ "," ++ String.fromInt point.y }, Cmd.none )

        Panned event ->
            ( { model | lastGesture = panLabel event }, Cmd.none )

        Swiped event ->
            ( { model | lastGesture = "Swipe " ++ directionLabel event.direction }, Cmd.none )


panLabel : Touch.PanEvent -> String
panLabel event =
    "Pan " ++ phaseLabel event.phase ++ " " ++ String.fromInt event.totalX ++ "," ++ String.fromInt event.totalY


phaseLabel : Touch.Phase -> String
phaseLabel phase =
    case phase of
        Touch.Started ->
            "start"

        Touch.Updated ->
            "move"

        Touch.Completed ->
            "end"

        Touch.Cancelled ->
            "cancel"


directionLabel : Touch.Direction -> String
directionLabel direction =
    case direction of
        Touch.Up ->
            "up"

        Touch.Down ->
            "down"

        Touch.Left ->
            "left"

        Touch.Right ->
            "right"


subscriptions : Model -> Sub Msg
subscriptions model =
    case model.supported of
        Just True ->
            Events.batch
                [ Touch.onTap Tapped
                , Touch.onPan Touch.Vertical Panned
                , Touch.onSwipe [ Touch.Left, Touch.Right ] Swiped
                , Button.onPress Button.Select SelectPressed
                ]

        _ ->
            Events.batch [ Button.onPress Button.Select SelectPressed ]


view : Model -> Ui.UiNode
view model =
    let
        textOpts =
            Ui.alignLeft Ui.defaultTextOptions
    in
    Ui.toUiNode
        [ Ui.clear Color.white
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 8, w = 136, h = 18 } "Touch"
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 32, w = 136, h = 18 } (supportedLabel model.supported)
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 56, w = 136, h = 18 } model.lastGesture
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 80, w = 136, h = 18 } "Tap / pan / swipe"
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 128, w = 136, h = 18 } "Sel: recheck"
        ]


supportedLabel : Maybe Bool -> String
supportedLabel maybeValue =
    case maybeValue of
        Nothing ->
            "Touch: --"

        Just True ->
            "Touch: yes"

        Just False ->
            "Touch: no"


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
