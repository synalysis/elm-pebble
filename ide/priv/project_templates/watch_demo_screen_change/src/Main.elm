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
    let
        textOpts =
            Ui.alignLeft Ui.defaultTextOptions
    in
    Ui.toUiNode
        [ Ui.clear Color.white
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 8, w = 136, h = 18 } "Screen"
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 28, w = 136, h = 18 } (String.fromInt model.screen.width ++ "x" ++ String.fromInt model.screen.height)
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 48, w = 136, h = 18 } (shapeLabel model.screen.shape)
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 68, w = 136, h = 18 } (colorLabel model.screen.colorMode)
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 88, w = 136, h = 18 } ("Chg: " ++ String.fromInt model.changes)
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 108, w = 136, h = 18 } "Switch model"
        ]


shapeLabel : DisplayShape -> String
shapeLabel shape =
    case shape of
        Round ->
            "Round"

        Rectangular ->
            "Rect"


colorLabel : ColorCapability -> String
colorLabel capability =
    case capability of
        Color ->
            "Color"

        BlackWhite ->
            "Mono"


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
