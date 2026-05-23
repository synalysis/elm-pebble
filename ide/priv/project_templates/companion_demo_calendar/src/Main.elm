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


type alias CalendarEvent =
    { title : String
    , hour : Int
    , minute : Int
    }


type alias Model =
    { timeString : String
    , nextEvent : Maybe CalendarEvent
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
      , nextEvent = Nothing
      , screenW = context.screen.width
      , screenH = context.screen.height
      }
    , Cmd.batch
        [ Cmd.getCurrentTimeString CurrentTimeString
        , CompanionWatch.sendWatchToPhone RequestCalendar
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        MinuteChanged _ ->
            ( model
            , Cmd.batch
                [ Cmd.getCurrentTimeString CurrentTimeString
                , CompanionWatch.sendWatchToPhone RequestCalendar
                ]
            )

        CurrentTimeString value ->
            ( { model | timeString = value }, Cmd.none )

        FromPhone (ProvideNextEvent title hour minute) ->
            ( { model | nextEvent = Just { title = title, hour = hour, minute = minute } }, Cmd.none )

        FromPhone NoUpcomingEvents ->
            ( { model | nextEvent = Nothing }, Cmd.none )


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

        eventLine =
            case model.nextEvent of
                Nothing ->
                    "No events"

                Just event ->
                    truncateTitle event.title 18
                        ++ " @ "
                        ++ formatClock event.hour event.minute
    in
    Ui.windowStack
        [ Ui.window 1
            [ Ui.canvasLayer 1
                [ Ui.clear Color.white
                , label 8 startY model.timeString
                , label 8 (startY + lineH) "Next event"
                , label 8 (startY + lineH * 2) eventLine
                ]
            ]
        ]


truncateTitle : String -> Int -> String
truncateTitle title maxLen =
    if String.length title <= maxLen then
        title

    else
        String.left (maxLen - 1) title ++ "…"


formatClock : Int -> Int -> String
formatClock hour minute =
    String.fromInt hour
        ++ ":"
        ++ (if minute < 10 then
                "0"

            else
                ""
           )
        ++ String.fromInt minute


main : Program Decode.Value Model Msg
main =
    Platform.watchface
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
