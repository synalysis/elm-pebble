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

        ( minuteX, minuteY ) =
            handEnd centerX centerY minuteRadius minuteIndex

        ( hourX, hourY ) =
            handEnd centerX centerY hourRadius hourIndex

        markerTop =
            handEnd centerX centerY radius 0

        markerRight =
            handEnd centerX centerY radius 3

        markerBottom =
            handEnd centerX centerY radius 6

        markerLeft =
            handEnd centerX centerY radius 9
    in
    PebbleUi.windowStack
        [ PebbleUi.window 1
            [ PebbleUi.canvasLayer 1
                [ PebbleUi.clear PebbleColor.white
                , PebbleUi.circle { x = centerX, y = centerY } radius PebbleColor.black
                , markerPixel markerTop
                , markerPixel markerRight
                , markerPixel markerBottom
                , markerPixel markerLeft
                , PebbleUi.line { x = centerX, y = centerY } { x = hourX, y = hourY } PebbleColor.black
                , PebbleUi.line { x = centerX, y = centerY } { x = minuteX, y = minuteY } PebbleColor.black
                , PebbleUi.fillCircle { x = centerX, y = centerY } 4 PebbleColor.black
                ]
            ]
        ]


markerPixel : ( Int, Int ) -> PebbleUi.RenderOp
markerPixel ( x, y ) =
    PebbleUi.pixel { x = x, y = y } PebbleColor.black


handEnd : Int -> Int -> Int -> Int -> ( Int, Int )
handEnd centerX centerY handRadius index =
    let
        ( ux, uy ) =
            unit12 index
    in
    ( centerX + ((ux * handRadius) // 1000)
    , centerY + ((uy * handRadius) // 1000)
    )


unit12 : Int -> ( Int, Int )
unit12 index =
    case modBy 12 index of
        0 ->
            ( 0, -1000 )

        1 ->
            ( 500, -866 )

        2 ->
            ( 866, -500 )

        3 ->
            ( 1000, 0 )

        4 ->
            ( 866, 500 )

        5 ->
            ( 500, 866 )

        6 ->
            ( 0, 1000 )

        7 ->
            ( -500, 866 )

        8 ->
            ( -866, 500 )

        9 ->
            ( -1000, 0 )

        10 ->
            ( -866, -500 )

        _ ->
            ( -500, -866 )


main : Program Decode.Value Model Msg
main =
    PebblePlatform.watchface
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
