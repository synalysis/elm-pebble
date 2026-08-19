module Main exposing (main)

import Json.Decode as Decode
import Pebble.Alarm as Alarm
import Pebble.Cmd as PebbleCmd
import Pebble.Events as PebbleEvents
import Pebble.Platform as PebblePlatform
import Pebble.Ui as PebbleUi
import Pebble.Ui.Color as PebbleColor
import Pebble.Ui.Resources as UiResources


type alias Model =
    { timeString : String
    , nextAlarmUtc : Maybe Int
    , screenW : Int
    , screenH : Int
    , displayShape : PebblePlatform.DisplayShape
    }


type Msg
    = MinuteChanged Int
    | CurrentTimeString String
    | GotNextAlarm Int


init : PebblePlatform.LaunchContext -> ( Model, Cmd Msg )
init context =
    ( { timeString = "--:--"
      , nextAlarmUtc = Nothing
      , screenW = context.screen.width
      , screenH = context.screen.height
      , displayShape = context.screen.shape
      }
    , Cmd.batch
        [ PebbleCmd.getCurrentTimeString CurrentTimeString
        , Alarm.next GotNextAlarm
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        MinuteChanged _ ->
            ( model
            , Cmd.batch
                [ PebbleCmd.getCurrentTimeString CurrentTimeString
                , Alarm.next GotNextAlarm
                ]
            )

        CurrentTimeString value ->
            ( { model | timeString = value }, Cmd.none )

        GotNextAlarm utcSeconds ->
            ( { model | nextAlarmUtc = Just utcSeconds }, Cmd.none )


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

        alarmY =
            min (cardY + cardH + 4) (model.screenH - 20)
    in
    PebbleUi.windowStack
        [ PebbleUi.window 1
            [ PebbleUi.canvasLayer 1
                ([ PebbleUi.clear PebbleColor.white
                 , PebbleUi.roundRect { x = cardX, y = cardY, w = cardW, h = cardH } cornerRadius PebbleColor.black
                 , PebbleUi.text UiResources.DefaultFont (PebbleUi.alignCenter PebbleUi.defaultTextOptions) { x = cardX, y = textY, w = cardW, h = timeH } model.timeString
                 ]
                    ++ alarmLine model alarmY cardX cardW
                )
            ]
        ]


alarmLine : Model -> Int -> Int -> Int -> List PebbleUi.RenderOp
alarmLine model alarmY cardX cardW =
    case model.nextAlarmUtc of
        Nothing ->
            []

        Just utcSeconds ->
            case Alarm.toPosix utcSeconds of
                Nothing ->
                    []

                Just _ ->
                    [ PebbleUi.text UiResources.DefaultFont (PebbleUi.alignCenter PebbleUi.defaultTextOptions) { x = cardX, y = alarmY, w = cardW, h = 18 } ("ALM " ++ formatUtcHm utcSeconds) ]


formatUtcHm : Int -> String
formatUtcHm utcSeconds =
    pad (remainderBy 24 (utcSeconds // 3600)) ++ ":" ++ pad (remainderBy 60 (utcSeconds // 60))


pad : Int -> String
pad value =
    if value < 10 then
        "0" ++ String.fromInt value

    else
        String.fromInt value


main : Program Decode.Value Model Msg
main =
    PebblePlatform.watchface
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
