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

{-| Enhanced hardware access for Pebble devices.

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


-- TYPES

{-| Types of vibration available.
-}
type VibrationType
    = Short       -- Quick buzz
    | Long        -- Extended vibration
    | Double      -- Two short buzzes
    | Nudge       -- Gentle notification


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


{-| Commands for hardware operations.
-}
type HardwareCmd msg
    = Vibrate VibrationType
    | VibratePattern VibrationPattern
    | SetBacklight BacklightLevel Int  -- level, duration_ms
    | GetBatteryLevel (Int -> msg)     -- 0-100
    | GetConnectionStatus (Bool -> msg) -- connected to phone
    | PlayTone Int Int                 -- frequency_hz, duration_ms
    | StopTone


-- VIBRATION

{-| Trigger a simple vibration.

    Hardware.vibrate Short

-}
vibrate : VibrationType -> HardwareCmd msg
vibrate vibrationType =
    Vibrate vibrationType


{-| Create a custom vibration pattern.

    -- Morse code SOS: ... --- ...
    sosPattern : VibrationPattern
    sosPattern =
        [ (150, 100), (150, 100), (150, 300)  -- ...
        , (400, 100), (400, 100), (400, 300)  -- ---
        , (150, 100), (150, 100), (150, 0)    -- ...
        ]
    
    Hardware.vibratePattern sosPattern

-}
vibratePattern : VibrationPattern -> HardwareCmd msg
vibratePattern pattern =
    VibratePattern pattern


-- BACKLIGHT

{-| Set backlight level for a specific duration.

    Hardware.setBacklight High 5000  -- High brightness for 5 seconds

-}
setBacklight : BacklightLevel -> Int -> HardwareCmd msg
setBacklight level duration =
    SetBacklight level duration


{-| Enable backlight at medium level for 3 seconds.

    Hardware.enableBacklight

-}
enableBacklight : HardwareCmd msg
enableBacklight =
    SetBacklight Medium 3000


{-| Turn off backlight immediately.

    Hardware.disableBacklight

-}
disableBacklight : HardwareCmd msg
disableBacklight =
    SetBacklight Off 0


{-| Flash backlight for attention.

    Hardware.flashBacklight  -- Quick bright flash

-}
flashBacklight : HardwareCmd msg
flashBacklight =
    SetBacklight Max 200


-- SYSTEM STATUS

{-| Get current battery level (0-100).

    Hardware.getBatteryLevel BatteryLevelReceived

-}
getBatteryLevel : (Int -> msg) -> HardwareCmd msg
getBatteryLevel toMsg =
    GetBatteryLevel toMsg


{-| Check if connected to phone via Bluetooth.

    Hardware.getConnectionStatus ConnectionStatusReceived

-}
getConnectionStatus : (Bool -> msg) -> HardwareCmd msg
getConnectionStatus toMsg =
    GetConnectionStatus toMsg


-- AUDIO

{-| Play a tone at specific frequency and duration.

    Hardware.playTone 440 1000  -- A4 note for 1 second

-}
playTone : Int -> Int -> HardwareCmd msg
playTone frequency duration =
    PlayTone frequency duration


{-| Stop any currently playing tone.

    Hardware.stopTone

-}
stopTone : HardwareCmd msg
stopTone =
    StopTone 