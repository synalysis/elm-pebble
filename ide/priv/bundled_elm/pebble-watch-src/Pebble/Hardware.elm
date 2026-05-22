module Pebble.Hardware exposing
    ( VibrationType(..)
    , VibrationPattern
    , BacklightLevel(..)
    , HardwareCmd(..)
    , vibrate
    , vibratePattern
    , setBacklight
    , enableBacklight
    , disableBacklight
    , flashBacklight
    , getBatteryLevel
    , getConnectionStatus
    , playTone
    , stopTone
    )

{-| Enhanced hardware access for Pebble watch devices.

# Types
@docs VibrationType, VibrationPattern, BacklightLevel, HardwareCmd

# Vibration
@docs vibrate, vibratePattern

# Backlight
@docs setBacklight, enableBacklight, disableBacklight, flashBacklight

# System Status
@docs getBatteryLevel, getConnectionStatus

# Audio (if supported)
@docs playTone, stopTone

-}


{-| Types of vibration available.
-}
type VibrationType
    = Short
    | Long
    | Double
    | Nudge


{-| Custom vibration patterns as a list of (duration_ms, pause_ms) pairs.
-}
type alias VibrationPattern =
    List ( Int, Int )


{-| Backlight intensity levels.
-}
type BacklightLevel
    = Off
    | Low
    | Medium
    | High
    | Max


{-| Commands for watch hardware operations.
-}
type HardwareCmd msg
    = Vibrate VibrationType
    | VibratePattern VibrationPattern
    | SetBacklight BacklightLevel Int
    | GetBatteryLevel (Int -> msg)
    | GetConnectionStatus (Bool -> msg)
    | PlayTone Int Int
    | StopTone


{-| Trigger a simple vibration.
-}
vibrate : VibrationType -> HardwareCmd msg
vibrate vibrationType =
    Vibrate vibrationType


{-| Create a custom vibration pattern.
-}
vibratePattern : VibrationPattern -> HardwareCmd msg
vibratePattern pattern =
    VibratePattern pattern


{-| Set backlight level for a specific duration.
-}
setBacklight : BacklightLevel -> Int -> HardwareCmd msg
setBacklight level duration =
    SetBacklight level duration


{-| Enable backlight at medium level for 3 seconds.
-}
enableBacklight : HardwareCmd msg
enableBacklight =
    SetBacklight Medium 3000


{-| Turn off backlight immediately.
-}
disableBacklight : HardwareCmd msg
disableBacklight =
    SetBacklight Off 0


{-| Flash backlight for attention.
-}
flashBacklight : HardwareCmd msg
flashBacklight =
    SetBacklight Max 200


{-| Get current battery level (0-100).
-}
getBatteryLevel : (Int -> msg) -> HardwareCmd msg
getBatteryLevel toMsg =
    GetBatteryLevel toMsg


{-| Check if connected to phone via Bluetooth.
-}
getConnectionStatus : (Bool -> msg) -> HardwareCmd msg
getConnectionStatus toMsg =
    GetConnectionStatus toMsg


{-| Play a tone at specific frequency and duration.
-}
playTone : Int -> Int -> HardwareCmd msg
playTone frequency duration =
    PlayTone frequency duration


{-| Stop any currently playing tone.
-}
stopTone : HardwareCmd msg
stopTone =
    StopTone
