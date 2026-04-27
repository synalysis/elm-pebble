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
    , isRound : Bool
    }


type Msg
    = MinuteChanged Int
    | CurrentTimeString String


init : PebblePlatform.LaunchContext -> ( Model, Cmd Msg )
init context =
    ( { timeString = "--:--"
      , screenW = context.screen.width
      , screenH = context.screen.height
      , isRound = context.screen.isRound
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
            (model.screenW * 7) // 10

        cardH =
            max 44 ((model.screenH * 56) // 168)

        cardX =
            (model.screenW - cardW) // 2

        cardY =
            (model.screenH - cardH) // 2

        cornerRadius =
            max 6 (min cardW cardH // 8)

        textX =
            cardX + (cardW // 6)

        textY =
            cardY + ((cardH * 2) // 3)
    in
    PebbleUi.windowStack
        [ PebbleUi.window 1
            [ PebbleUi.canvasLayer 1
                [ PebbleUi.clear PebbleColor.white
                , PebbleUi.roundRect { x = cardX, y = cardY, w = cardW, h = cardH } cornerRadius PebbleColor.black
                , PebbleUi.textLabel UiResources.DefaultFont { x = textX, y = textY } model.timeString
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
