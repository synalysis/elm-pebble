module Pebble.WatchInfo exposing
    ( FirmwareVersion
    , WatchColor(..)
    , WatchModel(..)
    , getColor
    , getFirmwareVersion
    , getModel
    )

{-| Access information about the watch itself.

This API mirrors Pebble's C `WatchInfo` module and provides information such as
watch model, watch color, and firmware version.

# Types
@docs WatchModel, FirmwareVersion, WatchColor

# Device info
@docs getModel, getFirmwareVersion, getColor

-}
import Elm.Kernel.PebbleWatch


{-| The model of the watch.

This corresponds to the C `WatchInfoModel` enum.
-}
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


{-| Firmware version of the watch.

This corresponds to the C `WatchInfoVersion` struct.

The version has the form `X.[X.[X]]`. When a version component is not present,
it is reported as `0`.

Examples:

  - `2.4.1` is represented as `{ major = 2, minor = 4, patch = 1 }`
  - `2.4` is represented as `{ major = 2, minor = 4, patch = 0 }`
-}
type alias FirmwareVersion =
    { major : Int
    , minor : Int
    , patch : Int
    }


{-| The case color of the watch.

This corresponds to the C `WatchInfoColor` enum.
-}
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


{-| Request the model of the current watch.

Equivalent to `watch_info_get_model()` in the C API.
-}
getModel : (WatchModel -> msg) -> Cmd msg
getModel =
    Elm.Kernel.PebbleWatch.getWatchModel


{-| Request the firmware version running on the watch.

Equivalent to `watch_info_get_firmware_version()` in the C API.
-}
getFirmwareVersion : (FirmwareVersion -> msg) -> Cmd msg
getFirmwareVersion =
    Elm.Kernel.PebbleWatch.getFirmwareVersion


{-| Request the case color of the current watch.

Equivalent to `watch_info_get_color()` in the C API.
-}
getColor : (WatchColor -> msg) -> Cmd msg
getColor =
    Elm.Kernel.PebbleWatch.getColor


