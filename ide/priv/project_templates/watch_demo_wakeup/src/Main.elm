module Main exposing (main)

import Json.Decode as Decode
import Pebble.Button as Button
import Pebble.Events as Events
import Pebble.Platform as Platform exposing (LaunchReason(..))
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources
import Pebble.Wakeup as Wakeup


type alias Model =
    { launchReason : LaunchReason
    , cancelId : Int
    , schedules : Int
    }


type Msg
    = SelectPressed
    | UpPressed
    | DownPressed


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init context =
    ( { launchReason = context.reason, cancelId = 0, schedules = 0 }, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SelectPressed ->
            ( { model | schedules = model.schedules + 1 }
            , Wakeup.scheduleAfterSeconds 15
            )

        UpPressed ->
            ( { model | cancelId = model.cancelId + 1 }, Cmd.none )

        DownPressed ->
            ( model, Wakeup.cancel model.cancelId )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Events.batch
        [ Button.onPress Button.Select SelectPressed
        , Button.onPress Button.Up UpPressed
        , Button.onPress Button.Down DownPressed
        ]


view : Model -> Ui.UiNode
view model =
    Ui.toUiNode
        [ Ui.clear Color.white
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 8, w = 136, h = 20 } "Wakeup demo"
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 32, w = 136, h = 20 } (launchLabel model.launchReason)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 56, w = 136, h = 20 } ("Scheduled: " ++ String.fromInt model.schedules)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 80, w = 136, h = 20 } ("Cancel id: " ++ String.fromInt model.cancelId)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 104, w = 136, h = 40 } "Select: +15s Up/Down: cancel id"
        ]


launchLabel : LaunchReason -> String
launchLabel reason =
    case reason of
        LaunchWakeup ->
            "Launched by wakeup"

        _ ->
            "Launched normally"


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
