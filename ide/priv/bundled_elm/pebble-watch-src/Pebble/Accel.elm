module Pebble.Accel exposing
    ( Config
    , Sample
    , SamplingRate(..)
    , defaultConfig
    , onData
    , onTap
    )

{-| Accelerometer subscriptions for Pebble watches.

Subscribe with `onData` for continuous samples and `onTap` for shake gestures.
Use `Pebble.Events.batch` to combine them with button or timer subscriptions.

    import Pebble.Accel as Accel
    import Pebble.Events as Events

    type Msg
        = AccelSample Accel.Sample
        | AccelTap

    subscriptions _ =
        Events.batch
            [ Accel.onData Accel.defaultConfig AccelSample
            , Accel.onTap AccelTap
            ]

For a runnable example, use the **watch-demo-accel** project template in the IDE.

# Types
@docs Config, Sample, SamplingRate

# Defaults
@docs defaultConfig

# Subscriptions
@docs onData, onTap

-}

import Elm.Kernel.PebbleWatch


{-| Accelerometer sampling rate.
-}
type SamplingRate
    = Hz10
    | Hz25
    | Hz50
    | Hz100


{-| Accelerometer sampling configuration.
-}
type alias Config =
    { samplesPerUpdate : Int
    , samplingRate : SamplingRate
    }


{-| One accelerometer sample.
-}
type alias Sample =
    { x : Int
    , y : Int
    , z : Int
    }


{-| Default configuration for interactive apps.
-}
defaultConfig : Config
defaultConfig =
    { samplesPerUpdate = 1
    , samplingRate = Hz25
    }


{-| Receive accelerometer samples.
-}
onData : Config -> (Sample -> msg) -> Sub msg
onData config toMsg =
    Elm.Kernel.PebbleWatch.onAccelData (samplingRateToInt config.samplingRate) toMsg


{-| Receive an accelerometer tap gesture.
-}
onTap : msg -> Sub msg
onTap =
    Elm.Kernel.PebbleWatch.onAccelTap


samplingRateToInt samplingRate =
    case samplingRate of
        Hz10 ->
            10

        Hz25 ->
            25

        Hz50 ->
            50

        Hz100 ->
            100
