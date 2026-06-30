module Main exposing (main)

import Json.Decode as Decode
import Pebble.Accel as Accel
import Pebble.Events as Events
import Pebble.Platform as Platform
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources
import Pebble.Vibes as Vibes


type alias Model =
    { x : Int
    , y : Int
    , z : Int
    , taps : Int
    }


type Msg
    = AccelSample Accel.Sample
    | AccelTap


accelConfig : Accel.Config
accelConfig =
    { samplesPerUpdate = 1, samplingRate = Accel.Hz50 }


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init _ =
    ( { x = 0, y = 0, z = -1000, taps = 0 }, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        AccelSample sample ->
            ( { model | x = sample.x, y = sample.y, z = sample.z }, Cmd.none )

        AccelTap ->
            ( { model | taps = model.taps + 1 }, Vibes.shortPulse )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Events.batch
        [ Accel.onData accelConfig AccelSample
        , Accel.onTap AccelTap
        ]


view : Model -> Ui.UiNode
view model =
    Ui.toUiNode
        [ Ui.clear Color.white
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 8, w = 136, h = 18 } "Accel demo"
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 32, w = 136, h = 18 } (String.fromInt model.x)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 52, w = 136, h = 18 } (String.fromInt model.y)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 72, w = 136, h = 18 } (String.fromInt model.z)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 96, w = 136, h = 18 } (String.fromInt model.taps)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 120, w = 136, h = 18 } "Tap to count"
        ]


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
