module Main exposing (main)

import Companion.Types exposing (PhoneToWatch(..), Theme(..), Units(..), WatchToPhone(..))
import Companion.Watch as CompanionWatch
import Json.Decode as Decode
import Pebble.Button as Button
import Pebble.Platform as Platform
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources


type alias Model =
    { theme : Maybe Theme
    , units : Maybe Units
    , screenW : Int
    , screenH : Int
    }


type Msg
    = FromPhone PhoneToWatch
    | SelectPressed


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init context =
    ( { theme = Nothing
      , units = Nothing
      , screenW = context.screen.width
      , screenH = context.screen.height
      }
    , CompanionWatch.sendWatchToPhone RequestStoredValues
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SelectPressed ->
            ( model, CompanionWatch.sendWatchToPhone CycleTheme )

        FromPhone (ProvideTheme theme units) ->
            ( { model | theme = Just theme, units = Just units }, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ CompanionWatch.onPhoneToWatch FromPhone
        , Button.onPress Button.Select SelectPressed
        ]


view : Model -> Ui.UiNode
view model =
    let
        lineH =
            18

        startY =
            36

        label x y text_ =
            Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = x, y = y, w = model.screenW - 16, h = lineH } text_
    in
    Ui.windowStack
        [ Ui.window 1
            [ Ui.canvasLayer 1
                [ Ui.clear Color.white
                , label 8 startY "Storage demo"
                , label 8 (startY + lineH) ("Theme " ++ themeLabel model.theme)
                , label 8 (startY + lineH * 2) ("Units " ++ unitsLabel model.units)
                , label 8 (startY + lineH * 3) "Select = cycle"
                ]
            ]
        ]


themeLabel : Maybe Theme -> String
themeLabel maybeTheme =
    case maybeTheme of
        Nothing ->
            "--"

        Just Dark ->
            "dark"

        Just Light ->
            "light"


unitsLabel : Maybe Units -> String
unitsLabel maybeUnits =
    case maybeUnits of
        Nothing ->
            "--"

        Just Metric ->
            "metric"

        Just Imperial ->
            "imperial"


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
