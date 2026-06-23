module Main exposing (main)

import Json.Decode as Decode
import Pebble.Button as Button
import Pebble.Events as Events
import Pebble.Log as Log
import Pebble.Platform as Platform
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources


type alias Model =
    { code : Int
    , emissions : Int
    }


type Msg
    = UpPressed
    | SelectPressed
    | DownPressed


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init _ =
    ( { code = 1000, emissions = 0 }, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UpPressed ->
            ( { model | code = model.code + 1 }, Cmd.none )

        DownPressed ->
            ( { model | code = max 0 (model.code - 1) }, Cmd.none )

        SelectPressed ->
            emit model


emit : Model -> ( Model, Cmd Msg )
emit model =
    let
        next =
            model.emissions + 1
    in
    ( { model | emissions = next }
    , Cmd.batch
        [ Log.infoCode model.code
        , Log.warnCode (model.code + 1)
        , Log.errorCode (model.code + 2)
        ]
    )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Events.batch
        [ Button.onPress Button.Up UpPressed
        , Button.onPress Button.Select SelectPressed
        , Button.onPress Button.Down DownPressed
        ]


view : Model -> Ui.UiNode
view model =
    Ui.toUiNode
        [ Ui.clear Color.white
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 8, w = 136, h = 20 } "Log demo"
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 36, w = 136, h = 20 } ("Code: " ++ String.fromInt model.code)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 64, w = 136, h = 20 } ("Sent: " ++ String.fromInt model.emissions)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 92, w = 136, h = 40 } "Select: emit info/warn/error"
        ]


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
