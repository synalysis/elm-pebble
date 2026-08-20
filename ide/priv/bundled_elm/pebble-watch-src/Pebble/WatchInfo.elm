module Pebble.WatchInfo exposing
    ( FirmwareVersion
    , WatchColor(..)
    , WatchModel(..)
    , caseColor
    , getColor
    , getFirmwareVersion
    , getModel
    )

{-| Access information about the watch itself.

This API mirrors Pebble's C `WatchInfo` module and provides information such as
watch model, watch color, and firmware version.

    import Pebble.WatchInfo as WatchInfo

    type Msg
        = GotModel WatchInfo.WatchModel
        | GotFirmware WatchInfo.FirmwareVersion
        | GotColor WatchInfo.WatchColor

    init _ =
        ( model
        , Cmd.batch
            [ WatchInfo.getModel GotModel
            , WatchInfo.getFirmwareVersion GotFirmware
            , WatchInfo.getColor GotColor
            ]
        )

For a runnable example, use the **watch-demo-watch-info** project template in the IDE.

# Types
@docs WatchModel, FirmwareVersion, WatchColor

# Device info
@docs getModel, getFirmwareVersion, getColor

# Drawing
@docs caseColor

-}
import Elm.Kernel.PebbleWatch
import Pebble.Ui.Color as Color


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


{-| Closest Pebble palette color for the watch case.

Use this for letterbox fills and other chrome that should match the body, not
the face. Unknown and black cases map to `Color.black`.
-}
caseColor : WatchColor -> Color.Color
caseColor color =
    case color of
        UnknownColor ->
            Color.black

        Black ->
            Color.black

        White ->
            Color.white

        Red ->
            Color.red

        Orange ->
            Color.orange

        Gray ->
            Color.lightGray

        StainlessSteel ->
            Color.lightGray

        MatteBlack ->
            Color.black

        Blue ->
            Color.blue

        Green ->
            Color.green

        Pink ->
            Color.brilliantRose

        TimeWhite ->
            Color.white

        TimeBlack ->
            Color.black

        TimeRed ->
            Color.red

        TimeSteelSilver ->
            Color.lightGray

        TimeSteelBlack ->
            Color.black

        TimeSteelGold ->
            Color.brass

        TimeRoundSilver14 ->
            Color.lightGray

        TimeRoundBlack14 ->
            Color.black

        TimeRoundSilver20 ->
            Color.lightGray

        TimeRoundBlack20 ->
            Color.black

        TimeRoundRoseGold14 ->
            Color.rajah

        Pebble2HrBlack ->
            Color.black

        Pebble2HrLime ->
            Color.springBud

        Pebble2HrFlame ->
            Color.sunsetOrange

        Pebble2HrWhite ->
            Color.white

        Pebble2HrAqua ->
            Color.tiffanyBlue

        Pebble2SeBlack ->
            Color.black

        Pebble2SeWhite ->
            Color.white

        PebbleTime2Black ->
            Color.black

        PebbleTime2Silver ->
            Color.lightGray

        PebbleTime2Gold ->
            Color.brass

        CoreDevicesP2DBlack ->
            Color.black

        CoreDevicesP2DWhite ->
            Color.white

        CoreDevicesPT2BlackGrey ->
            Color.black

        CoreDevicesPT2BlackRed ->
            Color.darkCandyAppleRed

        CoreDevicesPT2SilverBlue ->
            Color.cadetBlue

        CoreDevicesPT2SilverGrey ->
            Color.lightGray

        CoreDevicesPR2Black20 ->
            Color.black

        CoreDevicesPR2Silver20 ->
            Color.lightGray

        CoreDevicesPR2Gold14 ->
            Color.brass

        CoreDevicesPR2Silver14 ->
            Color.lightGray


