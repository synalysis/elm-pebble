module Main exposing (main)

import Json.Decode as Decode
import Pebble.Events as Events
import Pebble.Light as Light
import Pebble.Platform as Platform
import Pebble.Storage as Storage
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color


type alias Model =
    { score : Int }


type Msg
    = BestLoaded String


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init context =
    ( { score = 0 }
    , Cmd.batch
        [ Storage.readString 8347 BestLoaded
        , Light.enable
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        BestLoaded value ->
            ( { model | score = Maybe.withDefault 0 (String.toInt value) }, Cmd.none )


view : Model -> Ui.UiNode
view _ =
    Ui.toUiNode [ Ui.clear Color.white ]


subscriptions : Model -> Sub Msg
subscriptions _ =
    Events.batch []


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
