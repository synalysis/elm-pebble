module Main exposing (main)

import Json.Decode as Decode
import Pebble.Alarm as Alarm
import Pebble.Cmd as Cmd
import Pebble.Button as Button
import Pebble.Events as Events
import Pebble.Platform as Platform
import Pebble.Time as Time
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources


type alias Model =
    { clock : Maybe Time.CurrentDateTime
    , clock24h : Maybe Bool
    , timezoneSet : Maybe Bool
    , timezoneName : Maybe String
    , nextAlarmUtc : Maybe Int
    , refreshes : Int
    }


type Msg
    = SelectPressed
    | Tick
    | GotDateTime Time.CurrentDateTime
    | GotClock24h Bool
    | GotTimezoneSet Bool
    | GotTimezone String
    | GotNextAlarm Int


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init _ =
    ( { clock = Nothing
      , clock24h = Nothing
      , timezoneSet = Nothing
      , timezoneName = Nothing
      , nextAlarmUtc = Nothing
      , refreshes = 0
      }
    , requestTime
    )


requestTime : Cmd Msg
requestTime =
    Cmd.batch
        [ Time.currentDateTime GotDateTime
        , Time.clockStyle24h GotClock24h
        , Time.timezoneIsSet GotTimezoneSet
        , Time.timezone GotTimezone
        , Alarm.next GotNextAlarm
        ]


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SelectPressed ->
            ( { model | refreshes = model.refreshes + 1 }, requestTime )

        Tick ->
            ( { model | refreshes = model.refreshes + 1 }, requestTime )

        GotDateTime value ->
            ( { model | clock = Just value }, Cmd.none )

        GotClock24h value ->
            ( { model | clock24h = Just value }, Cmd.none )

        GotTimezoneSet value ->
            ( { model | timezoneSet = Just value }, Cmd.none )

        GotTimezone value ->
            ( { model | timezoneName = Just value }, Cmd.none )

        GotNextAlarm utcSeconds ->
            ( { model | nextAlarmUtc = Just utcSeconds }, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Events.batch [ Button.onPress Button.Select SelectPressed ]


view : Model -> Ui.UiNode
view model =
    let
        textOpts =
            Ui.alignLeft Ui.defaultTextOptions
    in
    Ui.toUiNode
        [ Ui.clear Color.white
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 8, w = 136, h = 18 } "Time"
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 32, w = 136, h = 18 } (timeLabel model.clock)
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 56, w = 136, h = 18 } (boolLabel "24h" model.clock24h)
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 80, w = 136, h = 18 } (timezoneLabel model.timezoneName)
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 104, w = 136, h = 18 } (alarmLabel model.nextAlarmUtc)
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 128, w = 136, h = 18 } "Sel: refresh"
        ]


timeLabel : Maybe Time.CurrentDateTime -> String
timeLabel maybeClock =
    case maybeClock of
        Nothing ->
            "--:--"

        Just clock ->
            pad clock.hour
                ++ ":"
                ++ pad clock.minute
                ++ ":"
                ++ pad clock.second


alarmLabel : Maybe Int -> String
alarmLabel maybeUtc =
    case maybeUtc of
        Nothing ->
            "Alarm: --"

        Just utcSeconds ->
            case Alarm.toPosix utcSeconds of
                Nothing ->
                    "Alarm: none"

                Just _ ->
                    "Alarm: " ++ formatUtcHm utcSeconds


formatUtcHm : Int -> String
formatUtcHm utcSeconds =
    pad (remainderBy 24 (utcSeconds // 3600)) ++ ":" ++ pad (remainderBy 60 (utcSeconds // 60))


timezoneLabel : Maybe String -> String
timezoneLabel maybeName =
    case maybeName of
        Nothing ->
            "TZ: --"

        Just name ->
            truncateTz name 14


truncateTz : String -> Int -> String
truncateTz text_ maxLen =
    if String.length text_ <= maxLen then
        text_

    else
        String.left maxLen text_


boolLabel : String -> Maybe Bool -> String
boolLabel label maybeValue =
    case maybeValue of
        Nothing ->
            label ++ ": --"

        Just True ->
            label ++ ": yes"

        Just False ->
            label ++ ": no"


pad : Int -> String
pad value =
    if value < 10 then
        "0" ++ String.fromInt value

    else
        String.fromInt value


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
