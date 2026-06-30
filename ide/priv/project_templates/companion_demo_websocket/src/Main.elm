module Main exposing (main)

import Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..), WebSocketStatus(..))
import Companion.Watch as CompanionWatch
import Json.Decode as Decode
import Pebble.Button as Button
import Pebble.Platform as Platform
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources


type alias Model =
    { status : WebSocketStatus
    , statusDetail : String
    , screenW : Int
    , screenH : Int
    }


type Msg
    = FromPhone PhoneToWatch
    | SelectPressed


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init context =
    ( { status = Closed
      , statusDetail = "waiting"
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

        FromPhone (ProvideWebSocketStatus status detail) ->
            ( { model | status = status, statusDetail = detail }, Cmd.none )


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

        textOpts =
            Ui.alignLeft Ui.defaultTextOptions

        label x y text_ =
            Ui.text Resources.DefaultFont textOpts { x = x, y = y, w = model.screenW - 16, h = lineH } text_
    in
    Ui.windowStack
        [ Ui.window 1
            [ Ui.canvasLayer 1
                [ Ui.clear Color.white
                , label 8 startY "WebSocket"
                , label 8 (startY + lineH) (statusLabel model.status)
                , label 8 (startY + lineH * 2) (truncate model.statusDetail 16)
                , label 8 (startY + lineH * 3) "Sel: ping"
                ]
            ]
        ]


truncate : String -> Int -> String
truncate text_ maxLen =
    if String.length text_ <= maxLen then
        text_

    else
        String.left maxLen text_


statusLabel : WebSocketStatus -> String
statusLabel status =
    case status of
        Closed ->
            "closed"

        Open ->
            "open"

        Error ->
            "error"


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
