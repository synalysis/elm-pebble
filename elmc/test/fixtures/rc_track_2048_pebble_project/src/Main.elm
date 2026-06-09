module Main exposing (main)

import List
import Pebble.Cmd
import Pebble.Platform exposing (LaunchContext)
import Pebble.Storage as Storage
import Pebble.Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources
import Platform
import RcTrack2048Probe as Board
import Sub


type alias Model =
    Board.Model


type Msg
    = LeftPressed
    | RightPressed
    | UpPressed
    | DownPressed


init : LaunchContext -> ( Model, Pebble.Cmd.Cmd Msg )
init _ =
    ( Board.initialModel 99, Pebble.Cmd.none )


update : Msg -> Model -> ( Model, Pebble.Cmd.Cmd Msg )
update msg model =
    let
        next =
            case msg of
                LeftPressed ->
                    Board.step 0 model

                RightPressed ->
                    Board.step 1 model

                UpPressed ->
                    Board.step 2 model

                DownPressed ->
                    Board.step 3 model
    in
    if next.best > model.best then
        ( next, Storage.writeString 2048 (String.fromInt next.best) )

    else
        ( next, Pebble.Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


view : Model -> Pebble.Ui.UiNode
view model =
    Pebble.Ui.toUiNode
        (Pebble.Ui.clear Color.white
            :: List.indexedMap drawCell model.cells
        )


drawCell : Int -> Int -> Pebble.Ui.RenderOp
drawCell index value =
    let
        cell =
            28

        gap =
            3

        x =
            10 + modBy 4 index * (cell + gap)

        y =
            26 + (index // 4) * (cell + gap)
    in
    Pebble.Ui.textInt Resources.DefaultFont { x = x, y = y } value


main : Platform.Program LaunchContext Msg Model
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }
