module Main exposing (main)

import Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))
import Companion.Watch as CompanionWatch
import Json.Decode as Decode
import Pebble.Cmd as Cmd
import Pebble.Events as Events
import Pebble.Platform as Platform
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources


type alias Model =
    { timeString : String
    , latitudeE6 : Int
    , longitudeE6 : Int
    , accuracyM : Int
    , screenW : Int
    , screenH : Int
    }


type Msg
    = MinuteChanged Int
    | CurrentTimeString String
    | FromPhone PhoneToWatch


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init context =
    ( { timeString = "--:--"
      , latitudeE6 = 0
      , longitudeE6 = 0
      , accuracyM = 0
      , screenW = context.screen.width
      , screenH = context.screen.height
      }
    , Cmd.batch
        [ Cmd.getCurrentTimeString CurrentTimeString
        , CompanionWatch.sendWatchToPhone RequestPosition
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        MinuteChanged _ ->
            ( model
            , Cmd.batch
                [ Cmd.getCurrentTimeString CurrentTimeString
                , CompanionWatch.sendWatchToPhone RequestPosition
                ]
            )

        CurrentTimeString value ->
            ( { model | timeString = value }, Cmd.none )

        FromPhone (ProvidePosition latitudeE6 longitudeE6 accuracyM) ->
            ( { model | latitudeE6 = latitudeE6, longitudeE6 = longitudeE6, accuracyM = accuracyM }, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Events.batch
        [ Events.onMinuteChange MinuteChanged
        , CompanionWatch.onPhoneToWatch FromPhone
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
                , label 8 startY model.timeString
                , label 8 (startY + lineH) ("Lat " ++ formatCoord model.latitudeE6)
                , label 8 (startY + lineH * 2) ("Lon " ++ formatCoord model.longitudeE6)
                , label 8 (startY + lineH * 3) ("±" ++ String.fromInt model.accuracyM ++ "m")
                ]
            ]
        ]


formatCoord : Int -> String
formatCoord micro =
    let
        negative =
            micro < 0

        value =
            abs micro

        whole =
            value // 1000000

        frac =
            modBy 1000000 value // 10000
    in
    (if negative then
        "-"

     else
        ""
    )
        ++ String.fromInt whole
        ++ "."
        ++ pad2 frac


pad2 : Int -> String
pad2 value =
    if value < 10 then
        "0" ++ String.fromInt value

    else
        String.fromInt value


main : Program Decode.Value Model Msg
main =
    Platform.watchface
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
