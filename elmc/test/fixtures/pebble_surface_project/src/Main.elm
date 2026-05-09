module Main exposing (coveredSurfaceFunctions, main)

import Json.Decode as Decode
import Pebble.Accel as PebbleAccel
import Pebble.Button as PebbleButton
import Pebble.Cmd as PebbleCmd
import Pebble.Events as PebbleEvents
import Pebble.Frame as PebbleFrame
import Pebble.Light as PebbleLight
import Pebble.Log as PebbleLog
import Pebble.Platform as PebblePlatform
import Pebble.Storage as PebbleStorage
import Pebble.System as PebbleSystem
import Pebble.Time as PebbleTime
import Pebble.Ui as PebbleUi
import Pebble.Ui.Color as PebbleColor
import Pebble.Ui.Resources as UiResources
import Pebble.Vibes as PebbleVibes
import Pebble.Wakeup as PebbleWakeup
import Pebble.WatchInfo as PebbleWatchInfo


type alias Model =
    { ticks : Int
    , latestTime : String
    }


type Msg
    = Tick Int
    | ButtonUp
    | ButtonSelect
    | ButtonDown
    | ButtonLongUp
    | ButtonLongSelect
    | ButtonLongDown
    | AccelTap
    | BatteryChanged Int
    | ConnectionChanged Bool
    | HourChanged Int
    | MinuteChanged Int
    | GotCurrentDateTime PebbleTime.CurrentDateTime
    | GotTime String
    | GotClockStyle24h Bool
    | GotTimezoneIsSet Bool
    | GotTimezone String
    | GotStoredInt Int
    | GotStorageString String
    | FrameTick PebbleFrame.Frame
    | UpPressed
    | UpReleased
    | AccelData PebbleAccel.Sample
    | GotWatchModel PebbleWatchInfo.WatchModel
    | GotWatchColor PebbleWatchInfo.WatchColor
    | GotFirmwareVersion PebbleWatchInfo.FirmwareVersion
    | GotBatteryLevel Int
    | GotConnectionStatus Bool


coveredSurfaceFunctions : List String
coveredSurfaceFunctions =
    [ "Pebble.Accel.defaultConfig"
    , "Pebble.Accel.onData"
    , "Pebble.Accel.onTap"
    , "Pebble.Button.on"
    , "Pebble.Button.onLongPress"
    , "Pebble.Button.onPress"
    , "Pebble.Button.onRelease"
    , "Pebble.Cmd.getCurrentDateTime"
    , "Pebble.Cmd.none"
    , "Pebble.Cmd.timerAfter"
    , "Pebble.Events.batch"
    , "Pebble.Events.onHourChange"
    , "Pebble.Events.onMinuteChange"
    , "Pebble.Events.onTick"
    , "Pebble.Frame.atFps"
    , "Pebble.Frame.every"
    , "Pebble.Light.disable"
    , "Pebble.Light.enable"
    , "Pebble.Light.interaction"
    , "Pebble.Log.errorCode"
    , "Pebble.Log.infoCode"
    , "Pebble.Log.warnCode"
    , "Pebble.Storage.delete"
    , "Pebble.Storage.readInt"
    , "Pebble.Storage.readString"
    , "Pebble.Storage.writeInt"
    , "Pebble.Storage.writeString"
    , "Pebble.System.batteryLevel"
    , "Pebble.System.connectionStatus"
    , "Pebble.System.onBatteryChange"
    , "Pebble.System.onConnectionChange"
    , "Pebble.Time.clockStyle24h"
    , "Pebble.Time.currentDateTime"
    , "Pebble.Time.currentTimeString"
    , "Pebble.Time.timezone"
    , "Pebble.Time.timezoneIsSet"
    , "Pebble.Vibes.cancel"
    , "Pebble.Vibes.doublePulse"
    , "Pebble.Vibes.longPulse"
    , "Pebble.Vibes.shortPulse"
    , "Pebble.Wakeup.cancel"
    , "Pebble.Wakeup.scheduleAfterSeconds"
    , "Pebble.WatchInfo.getColor"
    , "Pebble.WatchInfo.getFirmwareVersion"
    , "Pebble.WatchInfo.getModel"
    ]


parseHourFromTimeString : String -> Int
parseHourFromTimeString value =
    value
        |> String.left 2
        |> String.toInt
        |> Maybe.withDefault 0


init : PebblePlatform.LaunchContext -> ( Model, Cmd Msg )
init launchContext =
    let
        launchReasonValue =
            PebblePlatform.launchReasonToInt launchContext.reason
    in
    ( { ticks = launchReasonValue
      , latestTime = "00:00"
      }
    , Cmd.batch
        [ PebbleCmd.none
        , PebbleCmd.timerAfter 1000
        , PebbleCmd.getCurrentDateTime GotCurrentDateTime
        , PebbleTime.currentDateTime GotCurrentDateTime
        , PebbleTime.currentTimeString GotTime
        , PebbleTime.clockStyle24h GotClockStyle24h
        , PebbleTime.timezoneIsSet GotTimezoneIsSet
        , PebbleTime.timezone GotTimezone
        , PebbleStorage.writeInt 7 42
        , PebbleStorage.readInt 7 GotStoredInt
        , PebbleStorage.writeString 8 "saved"
        , PebbleStorage.readString 8 GotStorageString
        , PebbleStorage.delete 7
        , PebbleWatchInfo.getModel GotWatchModel
        , PebbleWatchInfo.getColor GotWatchColor
        , PebbleWatchInfo.getFirmwareVersion GotFirmwareVersion
        , PebbleSystem.batteryLevel GotBatteryLevel
        , PebbleSystem.connectionStatus GotConnectionStatus
        , PebbleLight.interaction
        , PebbleLight.disable
        , PebbleLight.enable
        , PebbleVibes.cancel
        , PebbleVibes.shortPulse
        , PebbleVibes.longPulse
        , PebbleVibes.doublePulse
        , PebbleWakeup.scheduleAfterSeconds 60
        , PebbleWakeup.cancel 1
        , PebbleLog.infoCode 101
        , PebbleLog.warnCode 202
        , PebbleLog.errorCode 303
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Tick _ ->
            ( { model | ticks = model.ticks + 1 }, PebbleCmd.timerAfter 1000 )

        ButtonUp ->
            ( model, PebbleStorage.writeInt 10 (model.ticks + 1) )

        ButtonSelect ->
            ( model
            , PebbleTime.currentTimeString GotTime
            )

        ButtonDown ->
            ( model, PebbleStorage.delete 10 )

        ButtonLongUp ->
            ( model, PebbleLog.infoCode 606 )

        ButtonLongSelect ->
            ( model, PebbleLog.warnCode 707 )

        ButtonLongDown ->
            ( model, PebbleLog.errorCode 808 )

        AccelTap ->
            ( model, PebbleVibes.shortPulse )

        BatteryChanged value ->
            let
                _ =
                    value
            in
            ( model, PebbleLog.infoCode 404 )

        ConnectionChanged value ->
            let
                _ =
                    value
            in
            ( model, PebbleLog.warnCode 505 )

        HourChanged value ->
            ( { model | ticks = value }, Cmd.none )

        MinuteChanged value ->
            ( { model | ticks = value }, Cmd.none )

        GotCurrentDateTime value ->
            ( { model | ticks = value.hour }, Cmd.none )

        GotTime value ->
            ( { model | latestTime = value, ticks = parseHourFromTimeString value }, Cmd.none )

        GotStoredInt value ->
            ( { model | ticks = value }, Cmd.none )

        GotStorageString value ->
            ( { model | latestTime = value }, Cmd.none )

        FrameTick frame ->
            ( { model | ticks = frame.frame }, Cmd.none )

        UpPressed ->
            ( { model | ticks = model.ticks + 1 }, Cmd.none )

        UpReleased ->
            ( model, Cmd.none )

        AccelData sample ->
            ( { model | ticks = sample.x + sample.y + sample.z }, Cmd.none )

        GotBatteryLevel value ->
            let
                _ =
                    value
            in
            ( model, Cmd.none )

        GotConnectionStatus value ->
            let
                _ =
                    value
            in
            ( model, Cmd.none )

        GotClockStyle24h _ ->
            ( model, Cmd.none )

        GotTimezoneIsSet _ ->
            ( model, Cmd.none )

        GotTimezone _ ->
            ( model, Cmd.none )

        GotWatchModel _ ->
            ( model, Cmd.none )

        GotWatchColor _ ->
            ( model, Cmd.none )

        GotFirmwareVersion _ ->
            ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    PebbleEvents.batch
        [ PebbleEvents.onTick Tick
        , PebbleButton.onPress PebbleButton.Up ButtonUp
        , PebbleButton.onPress PebbleButton.Select ButtonSelect
        , PebbleButton.onPress PebbleButton.Down ButtonDown
        , PebbleButton.onLongPress PebbleButton.Up ButtonLongUp
        , PebbleButton.onLongPress PebbleButton.Select ButtonLongSelect
        , PebbleButton.onLongPress PebbleButton.Down ButtonLongDown
        , PebbleEvents.onHourChange HourChanged
        , PebbleEvents.onMinuteChange MinuteChanged
        , PebbleAccel.onTap AccelTap
        , PebbleSystem.onBatteryChange BatteryChanged
        , PebbleSystem.onConnectionChange ConnectionChanged
        , PebbleFrame.every 33 FrameTick
        , PebbleFrame.atFps 30 FrameTick
        , PebbleButton.on PebbleButton.Up PebbleButton.Pressed UpPressed
        , PebbleButton.on PebbleButton.Up PebbleButton.Released UpReleased
        , PebbleButton.onRelease PebbleButton.Up UpReleased
        , PebbleAccel.onData PebbleAccel.defaultConfig AccelData
        ]


view : Model -> PebbleUi.UiNode
view model =
    let
        parsedInt =
            parseHourFromTimeString model.latestTime

        parsedFloatAsInt =
            "3.14"
                |> String.toFloat
                |> Maybe.withDefault 0
                |> floor
    in
    PebbleUi.windowStack
        [ PebbleUi.window 1
            [ PebbleUi.canvasLayer 1
                [ PebbleUi.clear PebbleColor.white
                , PebbleUi.textInt UiResources.DefaultFont { x = 0, y = 24 } parsedInt
                , PebbleUi.textInt UiResources.DefaultFont { x = 0, y = 48 } parsedFloatAsInt
                , PebbleUi.textInt UiResources.DefaultFont { x = 0, y = 72 } model.ticks
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
