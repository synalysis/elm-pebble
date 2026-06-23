module Main exposing (main)

import Json.Decode as Decode
import Pebble.Platform as Platform
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources
import Pebble.UnobstructedArea as UnobstructedArea


type alias Model =
    { bounds : Maybe Ui.Rect
    , progress : Maybe Int
    , phase : String
    , events : Int
    }


type Msg
    = GotBounds Ui.Rect
    | WillChange Ui.Rect
    | Changing Int
    | DidChange


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init _ =
    ( { bounds = Nothing, progress = Nothing, phase = "Starting", events = 0 }
    , UnobstructedArea.currentBounds GotBounds
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotBounds rect ->
            ( { model | bounds = Just rect, phase = "Current" }, Cmd.none )

        WillChange rect ->
            ( { model | bounds = Just rect, phase = "Will change", events = model.events + 1 }
            , Cmd.none
            )

        Changing progress ->
            ( { model | progress = Just progress, phase = "Changing" }, Cmd.none )

        DidChange ->
            ( { model | phase = "Did change", events = model.events + 1 }
            , UnobstructedArea.currentBounds GotBounds
            )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ UnobstructedArea.onWillChange WillChange
        , UnobstructedArea.onChanging Changing
        , UnobstructedArea.onDidChange DidChange
        ]


view : Model -> Ui.UiNode
view model =
    Ui.toUiNode
        [ Ui.clear Color.white
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 8, w = 136, h = 20 } "Unobstructed area"
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 32, w = 136, h = 20 } model.phase
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 56, w = 136, h = 20 } (rectLabel model.bounds)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 80, w = 136, h = 20 } ("Progress: " ++ maybeInt model.progress)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 104, w = 136, h = 40 } ("Events: " ++ String.fromInt model.events)
        ]


rectLabel : Maybe Ui.Rect -> String
rectLabel maybeRect =
    case maybeRect of
        Nothing ->
            "Bounds: --"

        Just rect ->
            "Bounds: "
                ++ String.fromInt rect.x
                ++ ","
                ++ String.fromInt rect.y
                ++ " "
                ++ String.fromInt rect.w
                ++ "x"
                ++ String.fromInt rect.h


maybeInt : Maybe Int -> String
maybeInt maybeValue =
    case maybeValue of
        Nothing ->
            "--"

        Just value ->
            String.fromInt value


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
