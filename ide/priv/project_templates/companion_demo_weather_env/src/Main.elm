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
    , temperatureC : Int
    , conditionCode : Int
    , sunriseMin : Int
    , sunsetMin : Int
    , moonPhaseE6 : Int
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
      , temperatureC = 0
      , conditionCode = 0
      , sunriseMin = 0
      , sunsetMin = 0
      , moonPhaseE6 = 0
      , screenW = context.screen.width
      , screenH = context.screen.height
      }
    , Cmd.batch
        [ Cmd.getCurrentTimeString CurrentTimeString
        , CompanionWatch.sendWatchToPhone RequestWeatherEnv
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        MinuteChanged _ ->
            ( model
            , Cmd.batch
                [ Cmd.getCurrentTimeString CurrentTimeString
                , CompanionWatch.sendWatchToPhone RequestWeatherEnv
                ]
            )

        CurrentTimeString value ->
            ( { model | timeString = value }, Cmd.none )

        FromPhone (ProvideWeather tempC conditionCode) ->
            ( { model | temperatureC = tempC, conditionCode = conditionCode }, Cmd.none )

        FromPhone (ProvideEnvironment sunriseMin sunsetMin moonPhaseE6) ->
            ( { model | sunriseMin = sunriseMin, sunsetMin = sunsetMin, moonPhaseE6 = moonPhaseE6 }, Cmd.none )


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
                , label 8 (startY + lineH) (String.fromInt model.temperatureC ++ "C " ++ conditionLabel model.conditionCode)
                , label 8 (startY + lineH * 2) ("Sun " ++ formatMinutes model.sunriseMin ++ "-" ++ formatMinutes model.sunsetMin)
                , label 8 (startY + lineH * 3) ("Moon " ++ String.fromInt (model.moonPhaseE6 // 10000) ++ "%")
                ]
            ]
        ]


conditionLabel : Int -> String
conditionLabel code =
    case code of
        0 ->
            "clear"

        1 ->
            "cloudy"

        2 ->
            "fog"

        3 ->
            "drizzle"

        4 ->
            "rain"

        5 ->
            "snow"

        6 ->
            "showers"

        7 ->
            "storm"

        _ ->
            "?"


formatMinutes : Int -> String
formatMinutes minutes =
    let
        hours =
            minutes // 60

        mins =
            modBy 60 minutes
    in
    String.fromInt hours
        ++ ":"
        ++ (if mins < 10 then
                "0"

            else
                ""
           )
        ++ String.fromInt mins


main : Program Decode.Value Model Msg
main =
    Platform.watchface
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
