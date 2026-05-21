module Main exposing (main)

import Pebble.Events as PebbleEvents
import Pebble.Platform as PebblePlatform
import Pebble.Ui as PebbleUi
import Pebble.Ui.Color as PebbleColor
import Pebble.Ui.Resources as UiResources
import Pebble.Cmd as PebbleCmd
import Json.Decode as Decode


type alias Model =
    { timeString : String
    , screenW : Int
    , screenH : Int
    , displayShape : PebblePlatform.DisplayShape
    }


type Msg
    = MinuteChanged Int
    | CurrentTimeString String


init : PebblePlatform.LaunchContext -> ( Model, Cmd Msg )
init context =
    ( { timeString = "--:--"
      , screenW = context.screen.width
      , screenH = context.screen.height
      , displayShape = context.screen.shape
      }
    , PebbleCmd.getCurrentTimeString CurrentTimeString
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        MinuteChanged _ ->
            ( model, PebbleCmd.getCurrentTimeString CurrentTimeString )

        CurrentTimeString value ->
            ( { model | timeString = value }, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    PebbleEvents.onMinuteChange MinuteChanged


view : Model -> PebbleUi.UiNode
view model =
    let
        cardW =
            (model.screenW * 17) // 20

        cardH =
            max 66 ((model.screenH * 70) // 168)

        cardX =
            (model.screenW - cardW) // 2

        cardY =
            (model.screenH - cardH) // 2

        cornerRadius =
            max 6 (min cardW cardH // 8)

        timeH =
            min 52 (cardH - 8)

        textY =
            cardY + ((cardH - timeH) // 2)
    in
    PebbleUi.windowStack
        [ PebbleUi.window 1
            [ PebbleUi.canvasLayer 1
                [ PebbleUi.clear PebbleColor.white
                , PebbleUi.roundRect { x = cardX, y = cardY, w = cardW, h = cardH } cornerRadius PebbleColor.black
                , PebbleUi.text UiResources.DefaultFont (PebbleUi.alignCenter PebbleUi.defaultTextOptions) { x = cardX, y = textY, w = cardW, h = timeH } model.timeString
                ]
            ]
        ]


main : Program Decode.Value Model Msg
main =
    PebblePlatform.watchface
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
