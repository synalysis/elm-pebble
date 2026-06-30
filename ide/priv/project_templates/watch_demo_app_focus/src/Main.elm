module Main exposing (main)

import Json.Decode as Decode
import Pebble.AppFocus as AppFocus
import Pebble.Platform as Platform
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources


type alias Model =
    { focus : Maybe AppFocus.State
    , changes : Int
    }


type Msg
    = FocusChanged AppFocus.State


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init _ =
    ( { focus = Nothing, changes = 0 }, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FocusChanged state ->
            ( { focus = Just state, changes = model.changes + 1 }, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    AppFocus.onChange FocusChanged


view : Model -> Ui.UiNode
view model =
    let
        textOpts =
            Ui.alignLeft Ui.defaultTextOptions
    in
    Ui.toUiNode
        [ Ui.clear Color.white
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 8, w = 136, h = 18 } "App focus"
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 32, w = 136, h = 18 } (focusLabel model.focus)
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 56, w = 136, h = 18 } (String.fromInt model.changes)
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 80, w = 136, h = 18 } "Toggle focus"
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 98, w = 136, h = 18 } "in simulator"
        ]


focusLabel : Maybe AppFocus.State -> String
focusLabel maybeFocus =
    case maybeFocus of
        Nothing ->
            "Starting"

        Just AppFocus.InFocus ->
            "In focus"

        Just AppFocus.OutOfFocus ->
            "Out of focus"


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
