module Main exposing (main)

import Pebble.Events as PebbleEvents
import Pebble.Platform as PebblePlatform
import Pebble.Ui as PebbleUi
import Pebble.Ui.Color as PebbleColor
import Pebble.Cmd as PebbleCmd
import Json.Decode as Decode


type alias Model =
    { hour : Int
    , minute : Int
    , screenW : Int
    , screenH : Int
    }


type Msg
    = CurrentDateTime PebbleCmd.CurrentDateTime
    | HourChanged Int
    | MinuteChanged Int


init : PebblePlatform.LaunchContext -> ( Model, Cmd Msg )
init context =
    ( { hour = 12
      , minute = 0
      , screenW = context.screen.width
      , screenH = context.screen.height
      }
    , PebbleCmd.getCurrentDateTime CurrentDateTime
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        CurrentDateTime value ->
            ( { model
                | hour = value.hour
                , minute = value.minute
              }
            , Cmd.none
            )

        HourChanged hour ->
            ( { model | hour = hour }, Cmd.none )

        MinuteChanged minute ->
            ( { model | minute = minute }, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    PebbleEvents.batch
        [ PebbleEvents.onHourChange HourChanged
        , PebbleEvents.onMinuteChange MinuteChanged
        ]


view : Model -> PebbleUi.UiNode
view model =
    let
        centerX =
            model.screenW // 2

        centerY =
            model.screenH // 2

        radius =
            max 22 ((min model.screenW model.screenH // 2) - 14)

        minuteRadius =
            (radius * 86) // 100

        hourRadius =
            (radius * 62) // 100

        minuteIndex =
            modBy 12 (model.minute // 5)

        hourIndex =
            modBy 12 (model.hour + (model.minute // 30))

        minuteX =
            handX centerX minuteRadius minuteIndex

        minuteY =
            handY centerY minuteRadius minuteIndex

        hourX =
            handX centerX hourRadius hourIndex

        hourY =
            handY centerY hourRadius hourIndex

        markerTopX =
            handX centerX radius 0

        markerTopY =
            handY centerY radius 0

        markerRightX =
            handX centerX radius 3

        markerRightY =
            handY centerY radius 3

        markerBottomX =
            handX centerX radius 6

        markerBottomY =
            handY centerY radius 6

        markerLeftX =
            handX centerX radius 9

        markerLeftY =
            handY centerY radius 9
    in
    PebbleUi.windowStack
        [ PebbleUi.window 1
            [ PebbleUi.canvasLayer 1
                [ PebbleUi.clear PebbleColor.white
                , PebbleUi.circle { x = centerX, y = centerY } radius PebbleColor.black
                , markerPixel markerTopX markerTopY
                , markerPixel markerRightX markerRightY
                , markerPixel markerBottomX markerBottomY
                , markerPixel markerLeftX markerLeftY
                , PebbleUi.line { x = centerX, y = centerY } { x = hourX, y = hourY } PebbleColor.black
                , PebbleUi.line { x = centerX, y = centerY } { x = minuteX, y = minuteY } PebbleColor.black
                , PebbleUi.fillCircle { x = centerX, y = centerY } 4 PebbleColor.black
                ]
            ]
        ]


markerPixel : Int -> Int -> PebbleUi.RenderOp
markerPixel x y =
    PebbleUi.pixel { x = x, y = y } PebbleColor.black


handX : Int -> Int -> Int -> Int
handX centerX handRadius index =
    centerX + ((unit12X index * handRadius) // 1000)


handY : Int -> Int -> Int -> Int
handY centerY handRadius index =
    centerY + ((unit12Y index * handRadius) // 1000)


unit12X : Int -> Int
unit12X index =
    case modBy 12 index of
        0 ->
            0

        1 ->
            500

        2 ->
            866

        3 ->
            1000

        4 ->
            866

        5 ->
            500

        6 ->
            0

        7 ->
            -500

        8 ->
            -866

        9 ->
            -1000

        10 ->
            -866

        _ ->
            -500


unit12Y : Int -> Int
unit12Y index =
    case modBy 12 index of
        0 ->
            -1000

        1 ->
            -866

        2 ->
            -500

        3 ->
            0

        4 ->
            500

        5 ->
            866

        6 ->
            1000

        7 ->
            866

        8 ->
            500

        9 ->
            0

        10 ->
            -500

        _ ->
            -866


main : Program Decode.Value Model Msg
main =
    PebblePlatform.watchface
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
