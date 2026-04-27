module Pebble.WatchInfo exposing
    ( FirmwareVersion
    , WatchColor(..)
    , WatchModel(..)
    , getColor
    , getFirmwareVersion
    , getModel
    )

import Elm.Kernel.PebbleWatch


type WatchModel
    = UnknownModel
    | PebbleOriginal
    | PebbleSteel
    | PebbleTime
    | PebbleTimeSteel
    | PebbleTimeRound14
    | PebbleTimeRound20
    | Pebble2Hr
    | Pebble2Se
    | PebbleTime2
    | CoreDevicesP2D
    | CoreDevicesPT2
    | CoreDevicesPR2


type alias FirmwareVersion =
    { major : Int
    , minor : Int
    , patch : Int
    }


type WatchColor
    = UnknownColor
    | Black
    | White
    | Red
    | Orange
    | Gray
    | StainlessSteel
    | MatteBlack
    | Blue
    | Green
    | Pink
    | TimeWhite
    | TimeBlack
    | TimeRed
    | TimeSteelSilver
    | TimeSteelBlack
    | TimeSteelGold
    | TimeRoundSilver14
    | TimeRoundBlack14
    | TimeRoundSilver20
    | TimeRoundBlack20
    | TimeRoundRoseGold14
    | Pebble2HrBlack
    | Pebble2HrLime
    | Pebble2HrFlame
    | Pebble2HrWhite
    | Pebble2HrAqua
    | Pebble2SeBlack
    | Pebble2SeWhite
    | PebbleTime2Black
    | PebbleTime2Silver
    | PebbleTime2Gold
    | CoreDevicesP2DBlack
    | CoreDevicesP2DWhite
    | CoreDevicesPT2BlackGrey
    | CoreDevicesPT2BlackRed
    | CoreDevicesPT2SilverBlue
    | CoreDevicesPT2SilverGrey
    | CoreDevicesPR2Black20
    | CoreDevicesPR2Silver20
    | CoreDevicesPR2Gold14
    | CoreDevicesPR2Silver14


getModel : (WatchModel -> msg) -> Cmd msg
getModel =
    Elm.Kernel.PebbleWatch.getWatchModel


getFirmwareVersion : (FirmwareVersion -> msg) -> Cmd msg
getFirmwareVersion =
    Elm.Kernel.PebbleWatch.getFirmwareVersion


getColor : (WatchColor -> msg) -> Cmd msg
getColor =
    Elm.Kernel.PebbleWatch.getColor


