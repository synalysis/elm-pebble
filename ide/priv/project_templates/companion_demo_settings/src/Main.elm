module Main exposing (main)

import Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))
import Companion.Watch as CompanionWatch
import Json.Decode as Decode
import Pebble.Button as Button
import Pebble.Platform as Platform
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources


type alias Model =
    { ready : Bool
    , configClosed : Bool
    , screenW : Int
    , screenH : Int
    }


type Msg
    = FromPhone PhoneToWatch
    | SelectPressed


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init context =
    ( { ready = False
      , configClosed = False
      , screenW = context.screen.width
      , screenH = context.screen.height
      }
    , Cmd.none
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SelectPressed ->
            ( model, CompanionWatch.sendWatchToPhone OpenSettings )

        FromPhone SettingsReady ->
            ( { model | ready = True }, Cmd.none )

        FromPhone (SettingsClosed closed) ->
            ( { model | configClosed = closed }, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ CompanionWatch.onPhoneToWatch FromPhone
        , Button.onPress Button.Select SelectPressed
        ]


view : Model -> Ui.UiNode
view model =
    let
        lineH =
            18

        startY =
            36

        label x y text_ =
            Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = x, y = y, w = model.screenW - 16, h = lineH } text_

        readyLabel =
            if model.ready then
                "ready"

            else
                "waiting"

        configLabel =
            if model.configClosed then
                "saved"

            else
                "none"
    in
    Ui.windowStack
        [ Ui.window 1
            [ Ui.canvasLayer 1
                [ Ui.clear Color.white
                , label 8 startY "Settings demo"
                , label 8 (startY + lineH) ("Lifecycle " ++ readyLabel)
                , label 8 (startY + lineH * 2) ("Config " ++ configLabel)
                , label 8 (startY + lineH * 3) "Select = open"
                ]
            ]
        ]


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
