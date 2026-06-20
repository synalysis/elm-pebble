module Main exposing (main)

import Json.Decode as Decode
import Pebble.Platform as Platform
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color


type alias Model =
    {}


type Msg
    = NoOp


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init _ =
    ( {}, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update _ model =
    ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


view : Model -> Ui.UiNode
view _ =
    Ui.toUiNode
        [ Ui.clear Color.white
        ]


main : Program Decode.Value Model Msg
main =
    Platform.watchface
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
