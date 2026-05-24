module Main exposing (main)

import Json.Decode as Decode
import Pebble.Button as Button
import Pebble.DataLog as DataLog
import Pebble.Events as Events
import Pebble.Platform as Platform
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources


type alias Model =
    { events : Int
    , lastValue : Int
    }


type Msg
    = UpPressed
    | SelectPressed
    | DownPressed


logTag : DataLog.Tag
logTag =
    DataLog.tag 9001


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init _ =
    ( { events = 0, lastValue = 0 }, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UpPressed ->
            logEvent { model | lastValue = model.events + 1 }

        SelectPressed ->
            logEvent { model | lastValue = model.events * 2 + 1 }

        DownPressed ->
            logBytes { model | lastValue = model.events + 10 }


logEvent : Model -> ( Model, Cmd Msg )
logEvent model =
    let
        next =
            { model | events = model.events + 1 }
    in
    ( next, DataLog.logInt32 logTag next.events )


logBytes : Model -> ( Model, Cmd Msg )
logBytes model =
    let
        next =
            { model | events = model.events + 1 }
    in
    ( next
    , DataLog.logBytes logTag [ next.events, next.lastValue, 42 ]
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
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 8, w = 136, h = 20 } "DataLog demo"
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 36, w = 136, h = 20 } (String.fromInt model.events)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 56, w = 136, h = 20 } (String.fromInt model.lastValue)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 84, w = 136, h = 40 } "Up: int32 Select: int32 Down: bytes"
        ]


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
