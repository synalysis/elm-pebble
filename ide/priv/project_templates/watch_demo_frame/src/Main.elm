module Main exposing (main)

import Json.Decode as Decode
import Pebble.Frame as Frame
import Pebble.Platform as Platform
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources


type alias Model =
    { frame : Int
    , elapsedMs : Int
    , dtMs : Int
    }


type Msg
    = Tick Frame.Frame


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init _ =
    ( { frame = 0, elapsedMs = 0, dtMs = 0 }, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Tick frame ->
            ( { frame = frame.frame, elapsedMs = frame.elapsedMs, dtMs = frame.dtMs }, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Frame.atFps 10 Tick


view : Model -> Ui.UiNode
view model =
    let
        textOpts =
            Ui.alignLeft Ui.defaultTextOptions
    in
    Ui.toUiNode
        [ Ui.clear Color.white
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 8, w = 136, h = 18 } "Frame"
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 32, w = 136, h = 18 } ("Frm: " ++ String.fromInt model.frame)
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 56, w = 136, h = 18 } ("Ms: " ++ String.fromInt model.elapsedMs)
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 80, w = 136, h = 18 } ("dt: " ++ String.fromInt model.dtMs)
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 104, w = 136, h = 18 } "10 fps"
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 122, w = 136, h = 18 } "Frame.atFps"
        ]


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
