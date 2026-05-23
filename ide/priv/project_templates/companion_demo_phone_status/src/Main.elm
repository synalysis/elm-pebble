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
    , batteryPercent : Int
    , charging : Bool
    , locale : String
    , online : Bool
    , notificationsEnabled : Bool
    , quietHours : Bool
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
      , batteryPercent = 0
      , charging = False
      , locale = "--"
      , online = False
      , notificationsEnabled = False
      , quietHours = False
      , screenW = context.screen.width
      , screenH = context.screen.height
      }
    , Cmd.batch
        [ Cmd.getCurrentTimeString CurrentTimeString
        , CompanionWatch.sendWatchToPhone RequestPhoneStatus
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        MinuteChanged _ ->
            ( model
            , Cmd.batch
                [ Cmd.getCurrentTimeString CurrentTimeString
                , CompanionWatch.sendWatchToPhone RequestPhoneStatus
                ]
            )

        CurrentTimeString value ->
            ( { model | timeString = value }, Cmd.none )

        FromPhone (ProvideBattery percent charging) ->
            ( { model | batteryPercent = percent, charging = charging }, Cmd.none )

        FromPhone (ProvideLocale locale) ->
            ( { model | locale = locale }, Cmd.none )

        FromPhone (ProvideConnectivity online) ->
            ( { model | online = online }, Cmd.none )

        FromPhone (ProvideNotifications enabled quietHours) ->
            ( { model | notificationsEnabled = enabled, quietHours = quietHours }, Cmd.none )


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
                , label 8 (startY + lineH) ("Bat " ++ String.fromInt model.batteryPercent ++ "% " ++ chargingLabel model.charging)
                , label 8 (startY + lineH * 2) ("Locale " ++ model.locale)
                , label 8 (startY + lineH * 3) ("Net " ++ onlineLabel model.online)
                , label 8 (startY + lineH * 4) ("Notif " ++ notificationLabel model.notificationsEnabled model.quietHours)
                ]
            ]
        ]


chargingLabel : Bool -> String
chargingLabel charging =
    if charging then
        "chg"

    else
        "idle"


onlineLabel : Bool -> String
onlineLabel online =
    if online then
        "online"

    else
        "offline"


notificationLabel : Bool -> Bool -> String
notificationLabel enabled quietHours =
    if quietHours then
        "quiet"

    else if enabled then
        "on"

    else
        "off"


main : Program Decode.Value Model Msg
main =
    Platform.watchface
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
