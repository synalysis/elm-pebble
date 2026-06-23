module Main exposing (main)

import Json.Decode as Decode
import Pebble.Platform as Platform exposing (ColorCapability(..), DisplayShape(..), LaunchScreen)
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources


type alias Model =
    { screen : LaunchScreen
    , changes : Int
    }


type Msg
    = ScreenChanged LaunchScreen


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init context =
    ( { screen = context.screen, changes = 0 }, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ScreenChanged screen ->
            ( { screen = screen, changes = model.changes + 1 }, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Platform.onScreenChange ScreenChanged


view : Model -> Ui.UiNode
view model =
    Ui.toUiNode
        [ Ui.clear Color.white
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 8, w = 136, h = 20 } "Screen change"
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 32, w = 136, h = 20 } (String.fromInt model.screen.width ++ "x" ++ String.fromInt model.screen.height)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 56, w = 136, h = 20 } (shapeLabel model.screen.shape)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 80, w = 136, h = 20 } (colorLabel model.screen.colorMode)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 104, w = 136, h = 20 } ("Changes: " ++ String.fromInt model.changes)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 128, w = 136, h = 20 } "Switch emulator model"
        ]


shapeLabel : DisplayShape -> String
shapeLabel shape =
    case shape of
        Round ->
            "Shape: round"

        Rectangular ->
            "Shape: rect"


colorLabel : ColorCapability -> String
colorLabel capability =
    case capability of
        Color ->
            "Color display"

        BlackWhite ->
            "Monochrome"


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
