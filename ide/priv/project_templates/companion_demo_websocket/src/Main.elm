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
    { statusCode : Int
    , statusText : String
    , screenW : Int
    , screenH : Int
    }


type Msg
    = FromPhone PhoneToWatch
    | SelectPressed


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init context =
    ( { statusCode = 0
      , statusText = "waiting"
      , screenW = context.screen.width
      , screenH = context.screen.height
      }
    , CompanionWatch.sendWatchToPhone RequestWebSocketStatus
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SelectPressed ->
            ( model, CompanionWatch.sendWatchToPhone PingWebSocket )

        FromPhone (ProvideWebSocketStatus code text) ->
            ( { model | statusCode = code, statusText = text }, Cmd.none )


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
    in
    Ui.windowStack
        [ Ui.window 1
            [ Ui.canvasLayer 1
                [ Ui.clear Color.white
                , label 8 startY "WebSocket demo"
                , label 8 (startY + lineH) (statusLabel model.statusCode)
                , label 8 (startY + lineH * 2) model.statusText
                , label 8 (startY + lineH * 3) "Select = ping"
                ]
            ]
        ]


statusLabel : Int -> String
statusLabel code =
    case code of
        1 ->
            "open"

        2 ->
            "error"

        _ ->
            "closed"


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
