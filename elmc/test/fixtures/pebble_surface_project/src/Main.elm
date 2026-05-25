module Main exposing (coveredSurfaceFunctions, main)

import Json.Decode as Decode
import Pebble.Accel as PebbleAccel
import Pebble.AppFocus as PebbleAppFocus
import Pebble.Button as PebbleButton
import Pebble.Cmd as PebbleCmd
import Pebble.Compass as PebbleCompass
import Pebble.DataLog as PebbleDataLog
import Pebble.Dictation as PebbleDictation
import Pebble.Events as PebbleEvents
import Pebble.Frame as PebbleFrame
import Pebble.Health as PebbleHealth
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
    | DayChanged Int
    | MonthChanged Int
    | YearChanged Int
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
    | GotHealthValue Int
    | GotHealthSumToday Int
    | GotHealthSum Int
    | GotHealthAccessible Bool
    | HealthEvent PebbleHealth.Event
    | AppFocusChanged PebbleAppFocus.State
    | CompassChanged PebbleCompass.Heading
    | GotCompassHeading (Result PebbleCompass.Error PebbleCompass.Heading)
    | DictationStatus PebbleDictation.Status
    | DictationResult (Result PebbleDictation.Error String)


coveredSurfaceFunctions : List String
coveredSurfaceFunctions =
    [ "Pebble.Accel.defaultConfig"
    , "Pebble.Accel.onData"
    , "Pebble.Accel.onTap"
    , "Pebble.AppFocus.onChange"
    , "Pebble.Compass.current"
    , "Pebble.Compass.onChange"
    , "Pebble.DataLog.tag"
    , "Pebble.DataLog.logBytes"
    , "Pebble.DataLog.logInt32"
    , "Pebble.Dictation.onResult"
    , "Pebble.Dictation.onStatus"
    , "Pebble.Dictation.start"
    , "Pebble.Dictation.stop"
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
    , "Pebble.Events.onSecondChange"
    , "Pebble.Events.onDayChange"
    , "Pebble.Events.onMonthChange"
    , "Pebble.Events.onYearChange"
    , "Pebble.Frame.atFps"
    , "Pebble.Frame.every"
    , "Pebble.Health.accessible"
    , "Pebble.Health.onEvent"
    , "Pebble.Health.supported"
    , "Pebble.Health.sum"
    , "Pebble.Health.sumToday"
    , "Pebble.Health.value"
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
    , "Pebble.Vibes.pattern"
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


highRateAccelConfig : PebbleAccel.Config
highRateAccelConfig =
    { samplesPerUpdate = 2
    , samplingRate = PebbleAccel.Hz100
    }


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
        , PebbleHealth.value PebbleHealth.StepCount GotHealthValue
        , PebbleHealth.sumToday PebbleHealth.StepCount GotHealthSumToday
        , PebbleHealth.sum PebbleHealth.WalkedDistanceMeters 0 3600 GotHealthSum
        , PebbleHealth.accessible PebbleHealth.ActiveSeconds 0 3600 GotHealthAccessible
        , PebbleLight.interaction
        , PebbleLight.disable
        , PebbleLight.enable
        , PebbleVibes.cancel
        , PebbleVibes.shortPulse
        , PebbleVibes.longPulse
        , PebbleVibes.doublePulse
        , PebbleVibes.pattern [ 100, 50, 100 ]
        , PebbleDataLog.logBytes (PebbleDataLog.tag 42) [ 1, 2, 3 ]
        , PebbleDataLog.logInt32 (PebbleDataLog.tag 43) 9001
        , PebbleCompass.current GotCompassHeading
        , PebbleDictation.start
        , PebbleDictation.stop
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

        DayChanged value ->
            ( { model | ticks = value }, Cmd.none )

        MonthChanged value ->
            ( { model | ticks = value }, Cmd.none )

        YearChanged value ->
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

        GotHealthValue value ->
            ( { model | ticks = value }, Cmd.none )

        GotHealthSumToday value ->
            ( { model | ticks = value }, Cmd.none )

        GotHealthSum value ->
            ( { model | ticks = value }, Cmd.none )

        GotHealthAccessible value ->
            let
                _ =
                    value
            in
            ( model, Cmd.none )

        HealthEvent event ->
            let
                _ =
                    event
            in
            ( model, Cmd.none )

        AppFocusChanged state ->
            let
                _ =
                    state
            in
            ( model, Cmd.none )

        CompassChanged heading ->
            let
                _ =
                    heading
            in
            ( model, Cmd.none )

        GotCompassHeading result ->
            let
                _ =
                    result
            in
            ( model, Cmd.none )

        DictationStatus status ->
            let
                _ =
                    status
            in
            ( model, Cmd.none )

        DictationResult result ->
            let
                _ =
                    result
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
        [ PebbleEvents.onSecondChange Tick
        , PebbleButton.onPress PebbleButton.Up ButtonUp
        , PebbleButton.onPress PebbleButton.Select ButtonSelect
        , PebbleButton.onPress PebbleButton.Down ButtonDown
        , PebbleButton.onLongPress PebbleButton.Up ButtonLongUp
        , PebbleButton.onLongPress PebbleButton.Select ButtonLongSelect
        , PebbleButton.onLongPress PebbleButton.Down ButtonLongDown
        , PebbleEvents.onHourChange HourChanged
        , PebbleEvents.onMinuteChange MinuteChanged
        , PebbleEvents.onDayChange DayChanged
        , PebbleEvents.onMonthChange MonthChanged
        , PebbleEvents.onYearChange YearChanged
        , PebbleAccel.onTap AccelTap
        , PebbleSystem.onBatteryChange BatteryChanged
        , PebbleSystem.onConnectionChange ConnectionChanged
        , PebbleFrame.every 33 FrameTick
        , PebbleFrame.atFps 30 FrameTick
        , PebbleButton.on PebbleButton.Up PebbleButton.Pressed UpPressed
        , PebbleButton.on PebbleButton.Up PebbleButton.Released UpReleased
        , PebbleButton.onRelease PebbleButton.Up UpReleased
        , PebbleAccel.onData highRateAccelConfig AccelData
        , PebbleAppFocus.onChange AppFocusChanged
        , PebbleCompass.onChange CompassChanged
        , PebbleDictation.onStatus DictationStatus
        , PebbleDictation.onResult DictationResult
        , PebbleHealth.onEvent HealthEvent
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
