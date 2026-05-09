module Elm.Kernel.PebbleWatch exposing
    ( backlight
    , batch
    , companionSend
    , getBatteryLevel
    , getClockStyle24h
    , getColor
    , getConnectionStatus
    , getCurrentDateTime
    , getCurrentTimeString
    , getFirmwareVersion
    , getTimezone
    , getTimezoneIsSet
    , getWatchModel
    , logErrorCode
    , logInfoCode
    , logWarnCode
    , none
    , onAccelData
    , onAccelTap
    , onBatteryChange
    , onButtonDown
    , onButtonLongDown
    , onButtonLongSelect
    , onButtonLongUp
    , onButtonRaw
    , onButtonSelect
    , onButtonUp
    , onConnectionChange
    , onFrame
    , onHourChange
    , onMinuteChange
    , onTick
    , storageDelete
    , storageReadInt
    , storageReadString
    , storageWriteInt
    , storageWriteString
    , timerAfter
    , vibesCancel
    , vibesDoublePulse
    , vibesLongPulse
    , vibesShortPulse
    , wakeupCancel
    , wakeupScheduleAfterSeconds
    )

{-| Kernel-backed watch primitives.

This module mirrors native-backed Pebble watch operations and is intended to
be consumed by public wrappers like `Pebble.Cmd` and `Pebble.Events`.

-}


none : Cmd msg
none =
    Cmd.none


timerAfter : Int -> Cmd msg
timerAfter ms =
    let
        keep =
            ms
    in
    Cmd.none


storageWriteInt : Int -> Int -> Cmd msg
storageWriteInt key value =
    let
        keep =
            key + value
    in
    Cmd.none


storageReadInt : Int -> (Int -> msg) -> Cmd msg
storageReadInt key toMsg =
    let
        keep =
            ( key, toMsg )
    in
    Cmd.none


storageDelete : Int -> Cmd msg
storageDelete key =
    let
        keep =
            key
    in
    Cmd.none


storageWriteString : Int -> String -> Cmd msg
storageWriteString key value =
    let
        keep =
            ( key, value )
    in
    Cmd.none


storageReadString : Int -> (String -> msg) -> Cmd msg
storageReadString key toMsg =
    let
        keep =
            ( key, toMsg )
    in
    Cmd.none


companionSend : Int -> Int -> Cmd msg
companionSend tag value =
    let
        keep =
            tag + value
    in
    Cmd.none


backlight : Maybe Bool -> Cmd msg
backlight mode =
    let
        keep =
            mode
    in
    Cmd.none


getCurrentTimeString : (String -> msg) -> Cmd msg
getCurrentTimeString toMsg =
    let
        keep =
            toMsg
    in
    Cmd.none


getCurrentDateTime : (a -> msg) -> Cmd msg
getCurrentDateTime toMsg =
    let
        keep =
            toMsg
    in
    Cmd.none


getBatteryLevel : (Int -> msg) -> Cmd msg
getBatteryLevel toMsg =
    let
        keep =
            toMsg
    in
    Cmd.none


getConnectionStatus : (Bool -> msg) -> Cmd msg
getConnectionStatus toMsg =
    let
        keep =
            toMsg
    in
    Cmd.none


getClockStyle24h : (Bool -> msg) -> Cmd msg
getClockStyle24h toMsg =
    let
        keep =
            toMsg
    in
    Cmd.none


getTimezoneIsSet : (Bool -> msg) -> Cmd msg
getTimezoneIsSet toMsg =
    let
        keep =
            toMsg
    in
    Cmd.none


getTimezone : (String -> msg) -> Cmd msg
getTimezone toMsg =
    let
        keep =
            toMsg
    in
    Cmd.none


getWatchModel : (a -> msg) -> Cmd msg
getWatchModel toMsg =
    let
        keep =
            toMsg
    in
    Cmd.none


getFirmwareVersion : (a -> msg) -> Cmd msg
getFirmwareVersion toMsg =
    let
        keep =
            toMsg
    in
    Cmd.none


getColor : (a -> msg) -> Cmd msg
getColor toMsg =
    let
        keep =
            toMsg
    in
    Cmd.none


logInfoCode : Int -> Cmd msg
logInfoCode code =
    let
        keep =
            code
    in
    Cmd.none


logWarnCode : Int -> Cmd msg
logWarnCode code =
    let
        keep =
            code
    in
    Cmd.none


logErrorCode : Int -> Cmd msg
logErrorCode code =
    let
        keep =
            code
    in
    Cmd.none


wakeupScheduleAfterSeconds : Int -> Cmd msg
wakeupScheduleAfterSeconds seconds =
    let
        keep =
            seconds
    in
    Cmd.none


wakeupCancel : Int -> Cmd msg
wakeupCancel wakeId =
    let
        keep =
            wakeId
    in
    Cmd.none


vibesCancel : Cmd msg
vibesCancel =
    Cmd.none


vibesShortPulse : Cmd msg
vibesShortPulse =
    Cmd.none


vibesLongPulse : Cmd msg
vibesLongPulse =
    Cmd.none


vibesDoublePulse : Cmd msg
vibesDoublePulse =
    Cmd.none


onTick : (Int -> msg) -> Sub msg
onTick _ =
    Sub.none


onFrame : Int -> (a -> msg) -> Sub msg
onFrame _ _ =
    Sub.none


onHourChange : (Int -> msg) -> Sub msg
onHourChange _ =
    Sub.none


onMinuteChange : (Int -> msg) -> Sub msg
onMinuteChange _ =
    Sub.none


onButtonUp : msg -> Sub msg
onButtonUp _ =
    Sub.none


onButtonSelect : msg -> Sub msg
onButtonSelect _ =
    Sub.none


onButtonDown : msg -> Sub msg
onButtonDown _ =
    Sub.none


onButtonRaw : Int -> Int -> msg -> Sub msg
onButtonRaw _ _ _ =
    Sub.none


onButtonLongUp : msg -> Sub msg
onButtonLongUp _ =
    Sub.none


onButtonLongSelect : msg -> Sub msg
onButtonLongSelect _ =
    Sub.none


onButtonLongDown : msg -> Sub msg
onButtonLongDown _ =
    Sub.none


onAccelTap : msg -> Sub msg
onAccelTap _ =
    Sub.none


onAccelData : Int -> (a -> msg) -> Sub msg
onAccelData _ _ =
    Sub.none


onBatteryChange : (Int -> msg) -> Sub msg
onBatteryChange _ =
    Sub.none


onConnectionChange : (Bool -> msg) -> Sub msg
onConnectionChange _ =
    Sub.none


batch : List (Sub msg) -> Sub msg
batch _ =
    Sub.none
