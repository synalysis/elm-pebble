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
    Ui.toUiNode
        [ Ui.clear Color.white
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 8, w = 136, h = 20 } "Frame demo"
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 36, w = 136, h = 20 } ("Frame: " ++ String.fromInt model.frame)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 64, w = 136, h = 20 } ("Elapsed: " ++ String.fromInt model.elapsedMs)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 92, w = 136, h = 20 } ("dt: " ++ String.fromInt model.dtMs ++ "ms")
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 120, w = 136, h = 20 } "10 fps via Frame.atFps"
        ]


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
