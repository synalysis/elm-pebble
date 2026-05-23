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
    { tokenPreview : String
    , statusCode : Int
    , screenW : Int
    , screenH : Int
    }


type Msg
    = FromPhone PhoneToWatch
    | SelectPressed


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init context =
    ( { tokenPreview = "loading"
      , statusCode = 0
      , screenW = context.screen.width
      , screenH = context.screen.height
      }
    , CompanionWatch.sendWatchToPhone RequestTimelineToken
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SelectPressed ->
            ( model, CompanionWatch.sendWatchToPhone InsertDemoPin )

        FromPhone (ProvideTimelineToken token) ->
            ( { model | tokenPreview = truncate token 20, statusCode = 0 }, Cmd.none )

        FromPhone (ProvideTimelineStatus code) ->
            ( { model | statusCode = code }, Cmd.none )


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

        statusText =
            if model.statusCode == 0 then
                "ok"

            else
                "error"
    in
    Ui.windowStack
        [ Ui.window 1
            [ Ui.canvasLayer 1
                [ Ui.clear Color.white
                , label 8 startY "Timeline demo"
                , label 8 (startY + lineH) ("Token " ++ model.tokenPreview)
                , label 8 (startY + lineH * 2) ("Pin " ++ statusText)
                , label 8 (startY + lineH * 3) "Select = insert"
                ]
            ]
        ]


truncate : String -> Int -> String
truncate text maxLen =
    if String.length text <= maxLen then
        text

    else
        String.left maxLen text ++ "…"


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
